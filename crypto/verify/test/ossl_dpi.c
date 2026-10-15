/* DPI-C：钉住提交的 OpenSSL EVP，以及结果文件比对。
   Verilator 会把该文件当 C++ 编译，导出名必须保持 C 链接。 */
#ifdef __cplusplus
extern "C" {
#endif

#include <openssl/crypto.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/provider.h>

#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int inited;

static uint8_t byte_at(const uint32_t* v, int width, int index) {
    int lsb = width - 8 * (index + 1);
    return (uint8_t)((v[lsb / 32] >> (lsb % 32)) & 0xff);
}

static void put_byte(uint32_t* v, int width, int index, uint8_t b) {
    int lsb = width - 8 * (index + 1);
    int word = lsb / 32;
    int off = lsb % 32;
    v[word] = (v[word] & ~(0xffu << off)) | ((uint32_t)b << off);
}

static const char* cipher_name(int cipher_id) {
    switch (cipher_id) {
    case 0: return "AES-256-ECB";
    case 1: return "AES-256-CTR";
    case 2: return "SM4-ECB";
    case 3: return "SM4-CTR";
    default: return NULL;
    }
}

int ossl_init(void) {
    if (inited)
        return 1;
    if (!OSSL_PROVIDER_load(NULL, "default")) {
        ERR_print_errors_fp(stderr);
        return 0;
    }
    inited = 1;
    printf("%s\n", OpenSSL_version(OPENSSL_VERSION));
    return 1;
}

int ossl_crypt(int is_enc, int cipher_id,
               const uint32_t* key, int key_len,
               const uint32_t* iv, int iv_valid,
               const uint32_t* din, int nbytes,
               uint32_t* dout) {
    const char* name = cipher_name(cipher_id);
    uint8_t key_b[32];
    uint8_t iv_b[16];
    uint8_t in_b[128];
    uint8_t out_b[160];
    const uint8_t* ivp = NULL;
    EVP_CIPHER* c = NULL;
    EVP_CIPHER_CTX* ctx = NULL;
    int out_len = 0;
    int fin = 0;
    int ok = 0;

    if (!inited || !name || !key || !din || !dout)
        return 0;
    if (nbytes <= 0 || nbytes > 128)
        return 0;
    if (key_len != 16 && key_len != 32)
        return 0;

    for (int i = 0; i < key_len; ++i)
        key_b[i] = byte_at(key, 256, i);
    for (int i = 0; i < nbytes; ++i)
        in_b[i] = byte_at(din, 1024, i);
    if (iv_valid) {
        if (!iv)
            return 0;
        for (int i = 0; i < 16; ++i)
            iv_b[i] = byte_at(iv, 128, i);
        ivp = iv_b;
    }

    c = EVP_CIPHER_fetch(NULL, name, NULL);
    ctx = EVP_CIPHER_CTX_new();
    if (c && ctx) {
        int rc = is_enc ? EVP_EncryptInit_ex(ctx, c, NULL, NULL, NULL)
                        : EVP_DecryptInit_ex(ctx, c, NULL, NULL, NULL);
        ok = rc == 1;
    }
    if (ok) {
        int rc = is_enc ? EVP_EncryptInit_ex(ctx, NULL, NULL, key_b, ivp)
                        : EVP_DecryptInit_ex(ctx, NULL, NULL, key_b, ivp);
        ok = rc == 1;
    }
    if (ok)
        ok = EVP_CIPHER_CTX_set_padding(ctx, 0) == 1;
    if (ok) {
        int rc = is_enc ? EVP_EncryptUpdate(ctx, out_b, &out_len, in_b, nbytes)
                        : EVP_DecryptUpdate(ctx, out_b, &out_len, in_b, nbytes);
        ok = rc == 1;
    }
    if (ok) {
        int rc = is_enc ? EVP_EncryptFinal_ex(ctx, out_b + out_len, &fin)
                        : EVP_DecryptFinal_ex(ctx, out_b + out_len, &fin);
        ok = rc == 1;
    }
    if (ok)
        ok = (out_len + fin) == nbytes;
    if (!ok)
        ERR_print_errors_fp(stderr);
    if (ok) {
        memset(dout, 0, (1024 / 32) * sizeof(uint32_t));
        for (int i = 0; i < nbytes; ++i)
            put_byte(dout, 1024, i, out_b[i]);
    }
    EVP_CIPHER_CTX_free(ctx);
    EVP_CIPHER_free(c);
    return ok;
}

static int rm_tree(const char* path) {
    DIR* dir = opendir(path);
    struct dirent* ent;
    if (!dir) {
        if (errno == ENOENT)
            return 0;
        return -1;
    }
    while ((ent = readdir(dir)) != NULL) {
        char child[4096];
        struct stat st;
        int n;
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
            continue;
        n = snprintf(child, sizeof(child), "%s/%s", path, ent->d_name);
        if (n < 0 || (size_t)n >= sizeof(child)) {
            closedir(dir);
            return -1;
        }
        if (lstat(child, &st) != 0) {
            closedir(dir);
            return -1;
        }
        if (S_ISDIR(st.st_mode)) {
            if (rm_tree(child) != 0) {
                closedir(dir);
                return -1;
            }
        } else if (remove(child) != 0) {
            closedir(dir);
            return -1;
        }
    }
    closedir(dir);
    return rmdir(path);
}

int clear_results(const char* path) {
    const char* slash;
    const char* base;
    if (!path || path[0] != '/')
        return 0;
    slash = strrchr(path, '/');
    base = slash ? slash + 1 : path;
    if (strcmp(base, "results") != 0 || strcmp(path, "/results") == 0)
        return 0;
    if (rm_tree(path) != 0)
        return 0;
    if (mkdir(path, 0755) != 0 && errno != EEXIST)
        return 0;
    return 1;
}

int ensure_dir(const char* path) {
    char buf[4096];
    size_t n;
    if (!path || !path[0])
        return 0;
    n = strlen(path);
    if (n >= sizeof(buf))
        return 0;
    memcpy(buf, path, n + 1);
    for (size_t i = 1; i <= n; ++i) {
        if (i == n || buf[i] == '/') {
            char save = buf[i];
            buf[i] = '\0';
            if (buf[0] != '\0' && mkdir(buf, 0755) != 0 && errno != EEXIST)
                return 0;
            buf[i] = save;
        }
    }
    return 1;
}

static int read_all(const char* path, char** body, size_t* len) {
    FILE* f = fopen(path, "rb");
    long n;
    char* buf;
    if (!f)
        return 0;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return 0;
    }
    n = ftell(f);
    if (n < 0 || n > 1024 * 1024) {
        fclose(f);
        return 0;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return 0;
    }
    buf = (char*)malloc((size_t)n + 1);
    if (!buf) {
        fclose(f);
        return 0;
    }
    if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return 0;
    }
    buf[n] = '\0';
    fclose(f);
    *body = buf;
    *len = (size_t)n;
    return 1;
}

static void line_at(const char* s, size_t len, size_t pos, char* out, size_t out_cap) {
    size_t start;
    size_t end;
    size_t n;
    if (len == 0 || out_cap == 0) {
        if (out_cap)
            out[0] = '\0';
        return;
    }
    if (pos >= len)
        pos = len - 1;
    start = pos;
    while (start > 0 && s[start - 1] != '\n')
        --start;
    end = pos;
    while (end < len && s[end] != '\n')
        ++end;
    n = end - start;
    if (n >= out_cap)
        n = out_cap - 1;
    memcpy(out, s + start, n);
    out[n] = '\0';
}

int results_match(const char* ref_path, const char* rtl_path, const char* cmp_path) {
    char* ref = NULL;
    char* rtl = NULL;
    size_t ref_len = 0;
    size_t rtl_len = 0;
    FILE* cmp;
    int same;
    size_t i;
    size_t n;
    int line;

    if (!read_all(ref_path, &ref, &ref_len) || !read_all(rtl_path, &rtl, &rtl_len)) {
        cmp = fopen(cmp_path, "wb");
        if (cmp) {
            fputs("result fail\nmissing result file\n", cmp);
            fclose(cmp);
        }
        free(ref);
        free(rtl);
        return 0;
    }
    same = (ref_len == rtl_len) && (memcmp(ref, rtl, ref_len) == 0);
    cmp = fopen(cmp_path, "wb");
    if (!cmp) {
        free(ref);
        free(rtl);
        return 0;
    }
    if (same) {
        fputs("result pass\n", cmp);
        fclose(cmp);
        free(ref);
        free(rtl);
        return 1;
    }

    n = ref_len < rtl_len ? ref_len : rtl_len;
    i = 0;
    line = 1;
    while (i < n && ref[i] == rtl[i]) {
        if (ref[i] == '\n')
            ++line;
        ++i;
    }
    {
        char ref_line[512];
        char rtl_line[512];
        line_at(ref, ref_len, i, ref_line, sizeof(ref_line));
        line_at(rtl, rtl_len, i, rtl_line, sizeof(rtl_line));
        fprintf(cmp, "result fail\nline %d\nref %s\nrtl %s\n", line, ref_line, rtl_line);
        printf("line %d\nref %s\nrtl %s\n", line, ref_line, rtl_line);
    }
    fclose(cmp);
    free(ref);
    free(rtl);
    return 0;
}

#ifdef __cplusplus
}
#endif

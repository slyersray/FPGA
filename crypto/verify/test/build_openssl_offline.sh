#!/usr/bin/env bash
# 用已拷入内网的源码编译钉住提交的静态 libcrypto，不访问网络。
# 在仓库根目录执行：
#   bash crypto/verify/test/build_openssl_offline.sh
#   bash crypto/verify/test/build_openssl_offline.sh /path/to/openssl.tar.gz
# 若 crypto/verify/work/openssl-src/Configure 已存在，则跳过解压。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORK="$ROOT/crypto/verify/work"
export PERL5LIB="$SCRIPT_DIR/perl5${PERL5LIB:+:$PERL5LIB}"
COMMIT="2506f1fc323b567b0e48a13b6069c7778077e55e"
PREFIX="$WORK/openssl-install"
SRC="$WORK/openssl-src"
TARBALL="${1:-}"

mkdir -p "$SCRIPT_DIR/perl5/IPC"
cat > "$SCRIPT_DIR/perl5/IPC/Cmd.pm" << 'END_IPC_CMD'
package IPC::Cmd;
use strict;
use File::Spec;

sub import { }

sub can_run {
    my ($command) = @_;
    return unless defined $command && length $command;

    if (File::Spec->file_name_is_absolute($command)) {
        return $command if -x $command && !-d _;
        return;
    }

    my @dirs = File::Spec->path;
    push @dirs, File::Spec->curdir;
    for my $dir (@dirs) {
        next if !defined $dir || $dir eq '' || !-d $dir;
        my $abs = File::Spec->catfile($dir, $command);
        return $abs if -x $abs && !-d _;
    }
    return;
}

1;
END_IPC_CMD

mkdir -p "$SCRIPT_DIR/perl5/Time"
cat > "$SCRIPT_DIR/perl5/Time/Piece.pm" << 'END_TIME_PIECE'
package Time::Piece;
use strict;

sub import {
    my $caller = caller;
    no strict 'refs';
    *{$caller . '::localtime'} = \&localtime;
    *{$caller . '::gmtime'} = \&gmtime;
}

sub localtime {
    shift if defined $_[0] && ($_[0] eq __PACKAGE__ || ref $_[0]);
    my $epoch = defined $_[0] ? $_[0] : time;
    return bless [CORE::localtime($epoch)], __PACKAGE__;
}

sub gmtime {
    shift if defined $_[0] && ($_[0] eq __PACKAGE__ || ref $_[0]);
    my $epoch = defined $_[0] ? $_[0] : time;
    return bless [CORE::gmtime($epoch)], __PACKAGE__;
}

sub strftime {
    my ($self, $fmt) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year) = @$self;
    $year += 1900;
    $mon += 1;
    my %map = (
        Y => sprintf('%04d', $year),
        m => sprintf('%02d', $mon),
        d => sprintf('%02d', $mday),
        H => sprintf('%02d', $hour),
        M => sprintf('%02d', $min),
        S => sprintf('%02d', $sec),
    );
    $fmt =~ s/%([YmdHMS])/$map{$1}/g;
    return $fmt;
}

sub strptime {
    my ($class, $string, $format) = @_;
    die "unsupported strptime format $format" if $format ne '%d %b %Y';
    my %month = (
        Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
        Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11,
    );
    my ($day, $mon_name, $year) = split ' ', $string;
    die "bad release date $string" if !defined $year || !exists $month{$mon_name};
    my $epoch = _ymd_to_epoch($year + 0, $month{$mon_name}, $day + 0);
    return bless [CORE::localtime($epoch)], $class;
}

sub _ymd_to_epoch {
    my ($year, $mon, $mday) = @_;
    my $days = 0;
    for (my $y = 1970; $y < $year; $y++) {
        $days += _leap($y) ? 366 : 365;
    }
    my @md = (31, _leap($year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
    for (my $m = 0; $m < $mon; $m++) {
        $days += $md[$m];
    }
    $days += $mday - 1;
    return $days * 86400;
}

sub _leap {
    my ($year) = @_;
    return $year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0);
}

1;
END_TIME_PIECE

if [[ -f "$PREFIX/COMMIT" && "$(cat "$PREFIX/COMMIT")" == "$COMMIT" && -f "$PREFIX/lib/libcrypto.a" && -f "$PREFIX/include/openssl/evp.h" ]]; then
    echo "openssl already built at $COMMIT"
    exit 0
fi

mkdir -p "$WORK"
rm -rf "$PREFIX"

if [[ -f "$SRC/Configure" ]]; then
    echo "using existing $SRC"
else
    if [[ -z "$TARBALL" ]]; then
        for c in \
            "$WORK/openssl-${COMMIT}.tar.gz" \
            "$WORK/openssl.tar.gz" \
            "$SCRIPT_DIR/openssl-${COMMIT}.tar.gz"
        do
            if [[ -f "$c" ]]; then
                TARBALL="$c"
                break
            fi
        done
    fi

    if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
        echo "找不到 OpenSSL 源码包，也没有已解压目录 $SRC" >&2
        echo "请把 openssl-${COMMIT}.tar.gz 放到 ${WORK}/ 后重新执行，或把路径作为参数传入。" >&2
        exit 1
    fi

    rm -rf "$SRC"
    echo "extracting $TARBALL"
    tar -xzf "$TARBALL" -C "$WORK"
    if [[ ! -d "$WORK/openssl-${COMMIT}" ]]; then
        echo "压缩包解开后没有目录 openssl-${COMMIT}" >&2
        exit 1
    fi
    mv "$WORK/openssl-${COMMIT}" "$SRC"
fi

cd "$SRC"
# no-asm 关掉 AVX-512/VAES 内联和汇编。参考库只需要可移植的 AES/SM4，
# 内网较旧的 gcc 编 aes_vaes512_intrinsics.c 会失败。
./Configure linux-x86_64 \
    --prefix="$PREFIX" \
    --libdir=lib \
    no-shared \
    no-asm \
    no-tests
make clean >/dev/null 2>&1 || true
if command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
else
    JOBS=4
fi
make -j"$JOBS" build_libs
make -j"$JOBS" install_dev
printf '%s\n' "$COMMIT" > "$PREFIX/COMMIT"

test -f "$PREFIX/lib/libcrypto.a"
test -f "$PREFIX/include/openssl/evp.h"
echo "OPENSSL_BUILD_OK $COMMIT"

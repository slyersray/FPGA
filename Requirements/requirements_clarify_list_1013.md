1. openSSL中 AES-256 支持模式： ECB、CBC、CBC-CTS、CFB / CFB1 / CFB8、OFB、CTR、XTS、CCM、GCM、OCB、SIV、GCM-SIV、WRAP 及其 PAD/INV 变体、CBC-HMAC-SHA1、CBC-HMAC-SHA256；只按照 ECB / CTR实现？不常见或者特定场景的不需要考虑。
2. openSSL中 SM4 支持模式：ECB、CBC、CFB、OFB、CTR、XTS、CCM、GCM； 按照 ECB / CTR实现？不常见或者特定场景的不需要考虑。
3. 报文。 一条流的数据是否总是 1024 bit 对齐？尾拍允许不足 8 个分组时，有效字节怎么标？
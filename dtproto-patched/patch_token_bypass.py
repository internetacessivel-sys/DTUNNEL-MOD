#!/usr/bin/env python3
"""Aplica/verifica o bypass de token no binario proto-server (DTProto).

O binario valida o token contra a API do fornecedor e, ao falhar, chama
log.Fatalf -> os.Exit -> runtime.exit -> exit_group, encerrando o processo.
Trocando o primeiro byte de runtime.exit por RET (0xC3), o log.Fatalf retorna
e o servidor segue para o caminho de sucesso (sem token).

Uso:
  python3 patch_token_bypass.py /usr/local/bin/proto-server          # aplica
  python3 patch_token_bypass.py /usr/local/bin/proto-server --check  # so verifica
  python3 patch_token_bypass.py /usr/local/bin/proto-server --revert # restaura .orig
"""
import os
import shutil
import sys

# mov edi, [rsp+8]; mov eax, 231 (exit_group); syscall; ret
STUB = bytes.fromhex("8b7c2408b8e70000000f05c3")
SYSCALL = bytes.fromhex("b8e70000000f05")
RET = 0xC3
PAD = 0xCC


def find_runtime_exit(data):
    """Retorna (offset_stub, offset_entry) ou (None, None)."""
    idx = data.find(SYSCALL)
    if idx < 4:
        return None, None
    # em Go cada funcao e precedida de padding 0xCC
    entry = idx - 4
    if entry > 0 and data[entry - 1] != PAD:
        return None, None
    head = bytes(data[entry:entry + 4])
    if head not in (b"\x8b\x7c\x24\x08", b"\xc3\x7c\x24\x08"):
        return None, None
    return entry, entry


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "--apply"

    data = bytearray(open(path, "rb").read())
    stub, entry = find_runtime_exit(data)

    if stub is None:
        print("ERRO: padrao do exit_group nao encontrado (versao/arquitetura diferente?)")
        print("      procure 'b8e70000000f05' e adapte STUB neste script")
        return 2

    patched = data[entry] == RET
    print("runtime.exit: stub=%#x entry=%#x" % (stub, entry))
    print("status: %s" % ("PATCHED" if patched else "ORIGINAL"))

    if mode == "--check":
        return 0 if patched else 3

    if mode == "--revert":
        bak = path + ".orig"
        if not os.path.exists(bak):
            print("ERRO: backup %s nao existe" % bak)
            return 4
        shutil.copy2(bak, path)
        print("revertido a partir de %s" % bak)
        return 0

    if patched:
        print("nada a fazer (ja patchado)")
        return 0

    bak = path + ".orig"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
        print("backup: %s" % bak)
    data[entry] = RET
    open(path, "wb").write(data)
    print("patch aplicado em %#x" % entry)
    return 0


if __name__ == "__main__":
    sys.exit(main())

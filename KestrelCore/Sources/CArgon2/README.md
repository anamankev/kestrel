# CArgon2

Argon2 reference implementation (portable `ref.c`, no SIMD), vendored unmodified from
https://github.com/P-H-C/phc-winner-argon2 at tag `20190702`, commit `62358ba2123abd17fccf2a108a301d4b52c01a7c`.
Licence: CC0 1.0 or Apache 2.0 (see LICENSE). Built with `ARGON2_NO_THREADS`: Kestrel uses one lane, so no
threads are created. KestrelCore checks it against the upstream Argon2id test vectors (`Argon2Tests`).

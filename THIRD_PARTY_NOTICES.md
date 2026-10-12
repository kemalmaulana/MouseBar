# Third-party notices

MouseBar is unofficial and not affiliated with SteelSeries or Logitech. It uses the work below. This file ships inside the app at `MouseBar.app/Contents/Resources/THIRD_PARTY_NOTICES.md`.

## rivalcfg (SteelSeries protocol and generated profiles)

MouseBar's SteelSeries protocol encoders and the data in `Sources/MouseCore/Generated/GeneratedProfiles.swift` come from [rivalcfg](https://github.com/flozz/rivalcfg) 4.17.0 by Fabien LOISON (flozz), licensed WTFPL. `Tools/gen_profiles.py` regenerates them.

```
            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>

 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
```

## OpenLogi (Logitech HID++ support)

The Logitech support links Rust crates from [OpenLogi](https://github.com/AprilNEA/OpenLogi) by AprilNEA (revision `0f69d75be99439da97291ff4163aba83dfc6df96`, version 0.8.13) through `Rust/mousebar-logi`: `openlogi-hid`, `openlogi-core`, `openlogi-hidpp` and their dependencies. OpenLogi is licensed `MIT OR Apache-2.0`; MouseBar uses it under the MIT licence:

```
MIT License

Copyright (c) 2026 AprilNEA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## hidpp (inside OpenLogi's `openlogi-hidpp`)

OpenLogi's `crates/openlogi-hidpp` is a fork of the `hidpp` crate from [logy](https://github.com/lus/logy) (forked at upstream v0.3.0), licensed 0BSD:

```
BSD Zero Clause License

Copyright (c) 2025 Lukas Schulte Pelkum

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
```

## Rust dependency tree of `Rust/mousebar-logi`

Every crate Cargo resolves for the `aarch64-apple-darwin` target (name, version, licence as declared in its manifest; the licence text of each is in its own repository). Generated from the repository root with:

```
cargo metadata --format-version 1 --locked --filter-platform aarch64-apple-darwin --manifest-path Rust/mousebar-logi/Cargo.toml | python3 -I -c 'import json,sys; m=json.load(sys.stdin); k={n["id"] for n in m["resolve"]["nodes"]}; [print("| %s | %s | %s |" % (p["name"], p["version"], p["license"] or "see crate")) for p in sorted(m["packages"], key=lambda p: (p["name"], p["version"])) if p["id"] in k and p["source"]]'
```

| Crate | Version | Licence |
|---|---|---|
| aho-corasick | 1.1.5 | Unlicense OR MIT |
| annotate-snippets | 0.12.16 | MIT OR Apache-2.0 |
| anstyle | 1.0.14 | MIT OR Apache-2.0 |
| arc-swap | 1.9.2 | MIT OR Apache-2.0 |
| arraydeque | 0.5.1 | MIT/Apache-2.0 |
| async-channel | 2.5.0 | Apache-2.0 OR MIT |
| async-trait | 0.1.92 | MIT OR Apache-2.0 |
| atomic-waker | 1.1.2 | Apache-2.0 OR MIT |
| atomic-write-file | 0.3.1 | BSD-3-Clause |
| autocfg | 1.5.1 | Apache-2.0 OR MIT |
| az | 1.3.0 | MIT/Apache-2.0 |
| base62 | 2.2.6 | MIT |
| base64 | 0.23.1 | MIT OR Apache-2.0 |
| bitflags | 1.3.2 | MIT/Apache-2.0 |
| bitflags | 2.13.2 | MIT OR Apache-2.0 |
| block2 | 0.6.2 | MIT |
| bstr | 1.13.1 | MIT OR Apache-2.0 |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| cfg_aliases | 0.2.2 | MIT |
| chacha20 | 0.10.2 | MIT OR Apache-2.0 |
| concurrent-queue | 2.5.0 | Apache-2.0 OR MIT |
| convert_case | 0.11.0 | MIT |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 |
| crossbeam-queue | 0.3.14 | MIT OR Apache-2.0 |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 |
| darling | 0.20.11 | MIT |
| darling_core | 0.20.11 | MIT |
| darling_macro | 0.20.11 | MIT |
| deranged | 0.5.8 | MIT OR Apache-2.0 |
| derive_builder | 0.20.2 | MIT OR Apache-2.0 |
| derive_builder_core | 0.20.2 | MIT OR Apache-2.0 |
| derive_builder_macro | 0.20.2 | MIT OR Apache-2.0 |
| derive_more | 2.1.1 | MIT |
| derive_more-impl | 2.1.1 | MIT |
| dispatch2 | 0.3.1 | Zlib OR Apache-2.0 OR MIT |
| displaydoc | 0.2.7 | MIT OR Apache-2.0 |
| either | 1.19.0 | MIT OR Apache-2.0 |
| encoding_rs | 0.8.42 | (Apache-2.0 OR MIT) AND BSD-3-Clause |
| encoding_rs_io | 0.1.8 | MIT OR Apache-2.0 |
| equivalent | 1.0.2 | Apache-2.0 OR MIT |
| etcetera | 0.11.0 | MIT OR Apache-2.0 |
| event-listener | 5.4.2 | Apache-2.0 OR MIT |
| event-listener-strategy | 0.5.4 | Apache-2.0 OR MIT |
| fastrand | 2.5.0 | Apache-2.0 OR MIT |
| fixedbitset | 0.5.7 | MIT OR Apache-2.0 |
| fluent-langneg | 0.14.2 | Apache-2.0 OR MIT |
| fnv | 1.0.7 | Apache-2.0 / MIT |
| foldhash | 0.2.0 | Zlib |
| futures | 0.3.34 | MIT OR Apache-2.0 |
| futures-channel | 0.3.34 | MIT OR Apache-2.0 |
| futures-concurrency | 7.7.1 | MIT OR Apache-2.0 |
| futures-core | 0.3.34 | MIT OR Apache-2.0 |
| futures-executor | 0.3.34 | MIT OR Apache-2.0 |
| futures-io | 0.3.34 | MIT OR Apache-2.0 |
| futures-lite | 2.6.1 | Apache-2.0 OR MIT |
| futures-macro | 0.3.34 | MIT OR Apache-2.0 |
| futures-sink | 0.3.34 | MIT OR Apache-2.0 |
| futures-task | 0.3.34 | MIT OR Apache-2.0 |
| futures-timer | 3.0.4 | MIT/Apache-2.0 |
| futures-util | 0.3.34 | MIT OR Apache-2.0 |
| getrandom | 0.4.3 | MIT OR Apache-2.0 |
| glob | 0.3.4 | MIT OR Apache-2.0 |
| globset | 0.4.20 | Unlicense OR MIT |
| globwalk | 0.8.1 | MIT |
| granit-parser | 1.3.0 | MIT OR Apache-2.0 |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 |
| heck | 0.5.0 | MIT OR Apache-2.0 |
| hex | 0.4.3 | MIT OR Apache-2.0 |
| hidreport | 0.5.0 | MIT |
| hut | 0.3.0 | MIT |
| icu_locid | 1.5.0 | Unicode-3.0 |
| ident_case | 1.0.1 | MIT/Apache-2.0 |
| ignore | 0.4.33 | Unlicense OR MIT |
| indexmap | 2.14.2 | Apache-2.0 OR MIT |
| itertools | 0.11.0 | MIT OR Apache-2.0 |
| itoa | 1.0.18 | MIT OR Apache-2.0 |
| kinded | 0.5.1 | MIT |
| kinded_macros | 0.5.1 | MIT |
| libc | 0.2.190 | MIT OR Apache-2.0 |
| litemap | 0.7.5 | Unicode-3.0 |
| log | 0.4.34 | MIT OR Apache-2.0 |
| memchr | 2.8.3 | Unlicense OR MIT |
| multiversion_no_op | 1.0.0 | Apache-2.0 OR MIT |
| nix | 0.31.3 | MIT |
| nohash-hasher | 0.2.0 | Apache-2.0 OR MIT |
| normpath | 1.5.2 | MIT OR Apache-2.0 |
| num-conv | 0.2.2 | MIT OR Apache-2.0 |
| num-traits | 0.2.19 | MIT OR Apache-2.0 |
| num_enum | 0.7.6 | BSD-3-Clause OR MIT OR Apache-2.0 |
| num_enum_derive | 0.7.6 | BSD-3-Clause OR MIT OR Apache-2.0 |
| nutype | 0.7.0 | MIT |
| nutype_macros | 0.7.0 | MIT |
| objc2 | 0.6.5 | MIT |
| objc2-core-foundation | 0.3.2 | Zlib OR Apache-2.0 OR MIT |
| objc2-encode | 4.1.0 | MIT |
| objc2-io-kit | 0.3.2 | Zlib OR Apache-2.0 OR MIT |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| openlogi-async-hid | 0.5.3-openlogi.1 | MIT |
| openlogi-core | 0.8.13 | MIT OR Apache-2.0 |
| openlogi-device | 0.8.13 | MIT OR Apache-2.0 |
| openlogi-device-registry | 0.8.13 | MIT OR Apache-2.0 |
| openlogi-fixture | 0.8.13 | MIT OR Apache-2.0 |
| openlogi-hid | 0.8.13 | MIT OR Apache-2.0 |
| openlogi-hidpp | 0.8.13 | 0BSD |
| openlogi-hidpp-derive | 0.8.13 | MIT OR Apache-2.0 |
| parking | 2.2.1 | Apache-2.0 OR MIT |
| pin-project | 1.1.13 | Apache-2.0 OR MIT |
| pin-project-internal | 1.1.13 | Apache-2.0 OR MIT |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT |
| plist | 1.10.1 | MIT |
| powerfmt | 0.2.1 | MIT OR Apache-2.0 |
| proc-macro-crate | 3.5.0 | MIT OR Apache-2.0 |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 |
| quick-xml | 0.42.0 | MIT |
| quote | 1.0.47 | MIT OR Apache-2.0 |
| rand | 0.10.3 | MIT OR Apache-2.0 |
| rand_core | 0.10.1 | MIT OR Apache-2.0 |
| regex | 1.13.1 | MIT OR Apache-2.0 |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 |
| rust-i18n | 4.2.4 | MIT |
| rust-i18n-macro | 4.2.4 | MIT |
| rust-i18n-support | 4.2.4 | MIT |
| rustc_version | 0.4.1 | MIT OR Apache-2.0 |
| rustversion | 1.0.23 | MIT OR Apache-2.0 |
| same-file | 1.0.6 | Unlicense/MIT |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 |
| semver | 1.0.28 | MIT OR Apache-2.0 |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde-saphyr | 1.3.0 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 |
| serde_ignored | 0.1.14 | MIT OR Apache-2.0 |
| serde_json | 1.0.154 | MIT OR Apache-2.0 |
| serde_spanned | 0.6.9 | MIT OR Apache-2.0 |
| simdutf8 | 0.1.5 | MIT OR Apache-2.0 |
| siphasher | 1.0.4 | MIT OR Apache-2.0 |
| slab | 0.4.12 | MIT |
| smallvec | 1.16.3 | MIT OR Apache-2.0 |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 |
| strsim | 0.11.1 | MIT |
| strum | 0.27.2 | MIT |
| strum_macros | 0.27.2 | MIT |
| syn | 2.0.119 | MIT OR Apache-2.0 |
| syn | 3.0.8 | MIT OR Apache-2.0 |
| sys-locale | 0.3.2 | MIT OR Apache-2.0 |
| thiserror | 1.0.69 | MIT OR Apache-2.0 |
| thiserror | 2.0.21 | MIT OR Apache-2.0 |
| thiserror-impl | 1.0.69 | MIT OR Apache-2.0 |
| thiserror-impl | 2.0.21 | MIT OR Apache-2.0 |
| time | 0.3.55 | MIT OR Apache-2.0 |
| time-core | 0.1.9 | MIT OR Apache-2.0 |
| time-macros | 0.2.32 | MIT OR Apache-2.0 |
| tinystr | 0.7.6 | Unicode-3.0 |
| tokio | 1.53.2 | MIT |
| tokio-macros | 2.7.2 | MIT |
| toml | 0.8.23 | MIT OR Apache-2.0 |
| toml_datetime | 0.6.11 | MIT OR Apache-2.0 |
| toml_datetime | 1.1.2+spec-1.1.0 | MIT OR Apache-2.0 |
| toml_edit | 0.22.27 | MIT OR Apache-2.0 |
| toml_edit | 0.25.17+spec-1.1.0 | MIT OR Apache-2.0 |
| toml_parser | 1.1.5+spec-1.1.0 | MIT OR Apache-2.0 |
| toml_write | 0.1.2 | MIT OR Apache-2.0 |
| tracing | 0.1.44 | MIT |
| tracing-attributes | 0.1.31 | MIT |
| tracing-core | 0.1.36 | MIT |
| triomphe | 0.1.17 | MIT OR Apache-2.0 |
| unicode-ident | 1.0.26 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| unicode-segmentation | 1.13.3 | MIT OR Apache-2.0 |
| unicode-width | 0.2.2 | MIT OR Apache-2.0 |
| urlencoding | 2.1.3 | MIT |
| walkdir | 2.5.0 | Unlicense/MIT |
| winnow | 0.7.15 | MIT |
| winnow | 1.0.4 | MIT |
| writeable | 0.5.5 | Unicode-3.0 |
| zmij | 1.0.23 | MIT |

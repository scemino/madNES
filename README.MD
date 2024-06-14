# madNES

A NES emulator for macOS, Linux, Windows and more.

## Compiling

With [fips](https://floooh.github.io/fips/)

```shell
./fips set target madNES
./fips gen
./fips build
./fips run
```

With [zig](https://ziglang.org/)

```shell
zig build run
```

## Controller

 Button        | Mapped to
 --------------|-------------
 Start         | Enter
 Select        | S
 A             | F
 B             | D
 Up            | Up
 Down          | Down
 Left          | Left
 Right         | Right

## Credits

Thanks to `flooh` for his libraries [chips](https://github.com/floooh/chips) & [sokol](https://github.com/floooh/sokol)

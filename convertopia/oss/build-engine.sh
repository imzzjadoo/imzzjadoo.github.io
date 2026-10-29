#!/bin/bash
WORK=${WORK:-$PWD}  # folder holding the NDK and the unpacked sources
# usage: build.sh <abi>
set -e
ABI=$1; NDK=$WORK/android-ndk-r27c; TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64; API=24
export PATH=/home/box/.local/bin:$TC/bin:$NDK/prebuilt/linux-x86_64/bin:$PATH
case $ABI in
 arm64-v8a) T=aarch64-linux-android; FA=aarch64; VPX=arm64-android-gcc; OA=arm64; CPU=armv8-a;;
 armeabi-v7a) T=armv7a-linux-androideabi; FA=arm; VPX=armv7-android-gcc; OA=arm; CPU=armv7-a;;
 x86_64) T=x86_64-linux-android; FA=x86_64; VPX=x86_64-android-gcc; OA=x86_64; CPU=x86-64;;
 x86) T=i686-linux-android; FA=x86; VPX=x86-android-gcc; OA=x86; CPU=i686;;
esac
P=$WORK/out/$ABI; mkdir -p $P; S=$WORK; J=8
export CC="$TC/bin/$T$API-clang" CXX="$TC/bin/$T$API-clang++" AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip NM=llvm-nm LD=ld.lld
export CFLAGS="-O3 -fPIC" CXXFLAGS="-O3 -fPIC" PKG_CONFIG_PATH=$P/lib/pkgconfig PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
HOST=$T; [ $ABI = armeabi-v7a ] && HOST=arm-linux-androideabi
B=$S/b/$ABI; mkdir -p $B
if [ -z "$SKIPDEPS" ]; then
ac() { d=$1; shift; mkdir -p $B/$d; cd $B/$d; $S/$d/configure --host=$HOST --prefix=$P --enable-static --disable-shared --with-pic "$@" >/dev/null; make -j$J >/dev/null; make install >/dev/null; }
ac lame-3.100 --disable-frontend --disable-decoder
ac libogg-1.3.5
ac libvorbis-1.3.7 --with-ogg=$P --disable-docs --disable-examples
ac opus-1.5.2 --disable-doc --disable-extra-programs
# libvpx
mkdir -p $B/vpx; cd $B/vpx; X=""; [ $OA = x86 -o $OA = x86_64 ] && X="--as=yasm"
VAS="$CC -c"; [ -n "$X" ] && VAS=yasm; AS="$CC" CROSS= $S/libvpx/configure --target=$VPX --prefix=$P --enable-pic --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp8 --enable-vp9 $X >/dev/null
make -j$J AS="$VAS" >/dev/null; make install >/dev/null
# openh264
rm -rf $B/oh; cp -r $S/openh264 $B/oh; cd $B/oh
OHA=""; [ $OA = x86 ] && OHA="USE_ASM=No"; [ $OA = x86_64 ] && OHA="USE_ASM=No"
make -j$J OS=android NDKROOT=$NDK TARGET=android-$API NDKLEVEL=$API ARCH=$OA $OHA PREFIX=$P libraries >/dev/null 2>&1 || { echo OHFAIL; make OS=android NDKROOT=$NDK TARGET=android-$API NDKLEVEL=$API ARCH=$OA $OHA libraries 2>&1 | tail -20; exit 1; }
make OS=android NDKROOT=$NDK TARGET=android-$API NDKLEVEL=$API ARCH=$OA $OHA PREFIX=$P install-static >/dev/null
sed -i 's/^Libs: .*/& -lc++_static -lc++abi -lm/' $P/lib/pkgconfig/openh264.pc
fi
# ffmpeg (LGPL only)
rm -rf $B/ff
mkdir -p $B/ff; cd $B/ff; XA=""; [ $OA = x86_64 ] && XA="--disable-x86asm"; [ $OA = x86 ] && XA="--disable-asm"
$S/ffmpeg-7.1.1/configure --prefix=$P/ff --target-os=android --arch=$FA --cpu=$CPU --enable-cross-compile --cc=$CC --cxx=$CXX --ar=llvm-ar --ranlib=llvm-ranlib --nm=llvm-nm --strip=llvm-strip \
  --pkg-config=pkg-config --pkg-config-flags=--static --enable-pic --enable-shared --disable-static --disable-symver --disable-doc --disable-ffplay --disable-ffprobe \
  --disable-indevs --disable-outdevs --enable-indev=lavfi --disable-network --disable-gpl --disable-nonfree --disable-version3 \
  --enable-libmp3lame --enable-libvorbis --enable-libopus --enable-libvpx --enable-libopenh264 \
  --extra-cflags="-I$P/include" --extra-ldflags="-L$P/lib" --extra-libs="-lm" $XA > cfg.log || { tail -30 ffbuild/config.log; exit 1; }
make -j$J >/dev/null 2>&1 || make 2>&1 | tail -30; make install >/dev/null
echo DONE $ABI

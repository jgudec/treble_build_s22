#!/bin/bash

echo
echo "--------------------------------------"
echo " Pixel Experience Plus 13.0 Buildbot  "
echo "                  by                  "
echo "                jgudec                "
echo "--------------------------------------"
echo

set -e

BL=$PWD/treble_build_pe
BD=$HOME/builds

export USE_CCACHE=1
export CCACHE_COMPRESS=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR=/mnt/ccache
export CCACHE_EXEC=$(command -v ccache)
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

SYNC=true

if [ $1 == "nosync" ]
then
    SYNC=false
fi

initRepos() {
    if [ ! -d .repo ]; then
        echo "--> Initializing workspace"
        repo init -u https://github.com/PixelExperience/manifest -b thirteen-plus
        echo

        echo "--> Preparing local manifest"
        mkdir -p .repo/local_manifests
        cp $BL/manifest.xml .repo/local_manifests/pixel.xml
        echo
    fi
}

syncRepos() {
    echo "--> Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
    echo
}

applyPatches() {
    echo "--> Applying prerequisite patches"
    bash $BL/apply-patches.sh $BL prerequisite
    echo

    echo "--> Applying TrebleDroid patches"
    bash $BL/apply-patches.sh $BL trebledroid
    echo

    echo "--> Applying personal patches"
    bash $BL/apply-patches.sh $BL personal
    echo

    echo "--> Generating makefiles"
    cd device/phh/treble
    cp $BL/pe.mk .
    bash generate.sh pe
    cd ../../..
    echo
}

setupEnv() {
    echo "--> Setting up build environment"
    source build/envsetup.sh &>/dev/null
    mkdir -p $BD
    echo
}

buildTrebleApp() {
    echo "--> Building treble_app"
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
    echo
}

buildVariant() {
    echo "--> Building treble_arm64_bvN"
    lunch treble_arm64_bvN-userdebug
    # make -j$(nproc --all) installclean
    make -j$(nproc --all) systemimage
    mv $OUT/system.img $BD/system-treble_arm64_bvN.img
    echo
}

generatePackages() {
    echo "--> Generating packages"
    buildDate="$(date +%Y%m%d)"
    xz -cv $BD/system-treble_arm64_bvN.img -T0 > $BD/PixelExperience_Plus_arm64-ab-13.0-$buildDate-UNOFFICIAL.img.xz
    rm -rf $BD/system-*.img
    echo
}

generateOta() {
    echo "--> Generating OTA file"
    version="$(date +v%Y.%m.%d)"
    timestamp="$START"
    json="{\"version\": \"$version\",\"date\": \"$timestamp\",\"variants\": ["
    find $BD/ -name "PixelExperience_Plus_*" | sort | {
        while read file; do
            filename="$(basename $file)"
            
            name="treble_arm64_bvN"
            size=$(wc -c $file | awk '{print $1}')
            url="https://github.com/jgudec/treble_build_GSI/releases/download/$version-plus/$filename"
            json="${json} {\"name\": \"$name\",\"size\": \"$size\",\"url\": \"$url\"},"
        done
        json="${json%?}]}"
        echo "$json" | jq . > $BL/ota.json
    }
    echo
}

START=$(date +%s)

if ${SYNC}
then
    initRepos
    syncRepos
    applyPatches
fi
setupEnv
buildTrebleApp
buildVariant
generatePackages
generateOta

END=$(date +%s)
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))

echo "--> Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo

#!/bin/bash
set -e

SOURCE_DIR=`pwd`
if [ -n "$1" ]; then
    SOURCE_DIR=$1
fi

cd ${SOURCE_DIR}

if [ "$BUILD_TARGERT" = "android" ]; then
    export ANDROID_SDK_ROOT=${SOURCE_DIR}/Tools/android-sdk
    export ANDROID_NDK_ROOT=${SOURCE_DIR}/Tools/android-ndk
    export ANDROID_SDK=${ANDROID_SDK_ROOT}
    export ANDROID_NDK=${ANDROID_NDK_ROOT}
    if [ -n "$APPVEYOR" ]; then
        export JAVA_HOME="/C/Program Files (x86)/Java/jdk1.8.0"
    fi
    if [ "$TRAVIS" = "true" ]; then
        export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
    fi
    case $BUILD_ARCH in
        arm*)
            export QT_ROOT=${SOURCE_DIR}/Tools/Qt/${QT_VERSION}/${QT_VERSION}/android_armv7
            ;;
        x86)
        export QT_ROOT=${SOURCE_DIR}/Tools/Qt/${QT_VERSION}/${QT_VERSION}/android_x86
        ;;
    esac
    export PATH=${SOURCE_DIR}/Tools/apache-ant/bin:$JAVA_HOME:$PATH
fi

if [ "${BUILD_TARGERT}" = "unix" ]; then
    if [ "$BUILD_DOWNLOAD" = "TRUE" ]; then
        QT_DIR=${SOURCE_DIR}/Tools/Qt/${QT_VERSION}
        export QT_ROOT=${QT_DIR}/${QT_VERSION}/gcc_64
    else
        #source /opt/qt${QT_VERSION_DIR}/bin/qt${QT_VERSION_DIR}-env.sh
        export QT_ROOT=/opt/qt${QT_VERSION_DIR}
    fi
    export PATH=$QT_ROOT/bin:$PATH
    export LD_LIBRARY_PATH=$QT_ROOT/lib/i386-linux-gnu:$QT_ROOT/lib:$LD_LIBRARY_PATH
    export PKG_CONFIG_PATH=$QT_ROOT/lib/pkgconfig:$PKG_CONFIG_PATH
fi

if [ "$BUILD_TARGERT" != "windows_msvc" ]; then
    RABBIT_MAKE_JOB_PARA="-j`cat /proc/cpuinfo |grep 'cpu cores' |wc -l`"  #make 同时工作进程参数
    if [ "$RABBIT_MAKE_JOB_PARA" = "-j1" ];then
        RABBIT_MAKE_JOB_PARA="-j2"
    fi
fi

if [ "$BUILD_TARGERT" = "windows_mingw" \
    -a -n "$APPVEYOR" ]; then
    export PATH=/C/Qt/Tools/mingw${TOOLCHAIN_VERSION}/bin:$PATH
fi
TARGET_OS=`uname -s`
case $TARGET_OS in
    MINGW* | CYGWIN* | MSYS*)
        export PKG_CONFIG=/c/msys64/mingw32/bin/pkg-config.exe
        ;;
    Linux* | Unix*)
    ;;
    *)
    ;;
esac

export PATH=${QT_ROOT}/bin:$PATH
echo "PATH:$PATH"
echo "PKG_CONFIG:$PKG_CONFIG"

echo "Build SeetaFace2 ......"
export SeetaFace2_SOURCE=${SOURCE_DIR}/../SeetaFace2
export SeetaFace2_DIR=${SeetaFace2_SOURCE}/install
git clone -b develop https://github.com/KangLin/SeetaFace2.git ${SeetaFace2_SOURCE}
cd ${SeetaFace2_SOURCE}

if [ -n "${STATIC}" ]; then
    CONFIG_PARA="-DBUILD_SHARED_LIBS=${STATIC}"
fi
echo "PWD:`pwd`"
if [ "${BUILD_TARGERT}" = "android" ]; then
    cmake -G"${GENERATORS}" ${SeetaFace2_SOURCE} ${CONFIG_PARA} \
         -DCMAKE_INSTALL_PREFIX=${SeetaFace2_DIR} \
         -DCMAKE_VERBOSE=ON \
         -DCMAKE_BUILD_TYPE=Release \
         -DBUILD_EXAMPLE=OFF \
         -DANDROID_PLATFORM=${ANDROID_API} -DANDROID_ABI="${BUILD_ARCH}" \
         -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake 
else
    cmake -G"${GENERATORS}" ${SeetaFace2_SOURCE} ${CONFIG_PARA} \
         -DCMAKE_INSTALL_PREFIX=${SeetaFace2_DIR} \
         -DCMAKE_VERBOSE=ON \
         -DCMAKE_BUILD_TYPE=Release \
         -DBUILD_EXAMPLE=OFF
fi
cmake --build . --target install --config Release

cd ${SOURCE_DIR}

mkdir -p build_${BUILD_TARGERT}
cd build_${BUILD_TARGERT}

case ${BUILD_TARGERT} in
    windows_msvc)
        MAKE=nmake
        ;;
    windows_mingw)
        if [ "${RABBIT_BUILD_HOST}"="windows" ]; then
            MAKE="mingw32-make ${RABBIT_MAKE_JOB_PARA}"
        fi
        ;;
    *)
        MAKE="make ${RABBIT_MAKE_JOB_PARA}"
        ;;
esac

export VERSION="v0.0.2"
if [ "${BUILD_TARGERT}" = "unix" ]; then
    cd $SOURCE_DIR
    bash build_debpackage.sh ${QT_ROOT}

    sudo dpkg -i ../facerecognizer_*_amd64.deb
    echo "test ......"
    ./test/test_linux.sh

    #因为上面 dpgk 已安装好了，所以不需要设置下面的环境变量
    export LD_LIBRARY_PATH=${SeetaFace2_DIR}/bin:${SeetaFace2_DIR}/lib:${QT_ROOT}/bin:${QT_ROOT}/lib:$LD_LIBRARY_PATH
    
    cd debian/facerecognizer/opt
    
    URL_LINUXDEPLOYQT=https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage
    wget -c -nv ${URL_LINUXDEPLOYQT} -O linuxdeployqt.AppImage
    chmod a+x linuxdeployqt.AppImage

    cd FaceRecognizer
    ../linuxdeployqt.AppImage share/applications/*.desktop \
        -qmake=${QT_ROOT}/bin/qmake -appimage -no-copy-copyright-files -verbose

    # Create appimage install package
    #cp ../FaceRecognizer-${VERSION}-x86_64.AppImage .
    cp $SOURCE_DIR/Install/install.sh .
    ln -s FaceRecognizer-${VERSION}-x86_64.AppImage FaceRecognizer-x86_64.AppImage
    tar -czf FaceRecognizer_${VERSION}.tar.gz \
        FaceRecognizer-${VERSION}-x86_64.AppImage \
        FaceRecognizer-x86_64.AppImage \
        share \
        install.sh

    # Create update.xml
    MD5=`md5sum $SOURCE_DIR/../facerecognizer_*_amd64.deb|awk '{print $1}'`
    echo "MD5:${MD5}"
    ./bin/FaceRecognizerApp \
        -f "`pwd`/update_linux.xml" \
        --md5 ${MD5}
    cat update_linux.xml
    
    MD5=`md5sum FaceRecognizer_${VERSION}.tar.gz|awk '{print $1}'`
    ./FaceRecognizer-x86_64.AppImage \
        -f "`pwd`/update_linux_appimage.xml" \
        --md5 ${MD5} \
        --url "https://github.com/KangLin/FaceRecognizer/releases/download/${VERSION}/FaceRecognizer_${VERSION}.tar.gz"
    cat update_linux_appimage.xml
    
    if [ "$TRAVIS_TAG" != "" -a "${QT_VERSION_DIR}" = "512" ]; then
        export UPLOADTOOL_BODY="Release FaceRecognizer-${VERSION}"
        #export UPLOADTOOL_PR_BODY=
        wget -c https://github.com/probonopd/uploadtool/raw/master/upload.sh
        chmod u+x upload.sh
        ./upload.sh $SOURCE_DIR/../facerecognizer_*_amd64.deb 
        ./upload.sh update_linux.xml update_linux_appimage.xml
        ./upload.sh FaceRecognizer_${VERSION}.tar.gz
    fi
    exit 0
fi

if [ -n "$GENERATORS" ]; then
    if [ -n "${STATIC}" ]; then
        CONFIG_PARA="-DBUILD_SHARED_LIBS=${STATIC}"
    fi

    echo "Build FaceRecognizer ......"
    cd ${SOURCE_DIR}
    echo "PWD:`pwd`"
    if [ "${BUILD_TARGERT}" = "android" ]; then
    	 cmake -G"${GENERATORS}" ${SOURCE_DIR} ${CONFIG_PARA} \
            -DCMAKE_INSTALL_PREFIX=`pwd`/install \
            -DCMAKE_VERBOSE=ON \
            -DCMAKE_BUILD_TYPE=Release \
            -DQt5_DIR=${QT_ROOT}/lib/cmake/Qt5 \
            -DQt5Core_DIR=${QT_ROOT}/lib/cmake/Qt5Core \
            -DQt5Gui_DIR=${QT_ROOT}/lib/cmake/Qt5Gui \
            -DQt5Widgets_DIR=${QT_ROOT}/lib/cmake/Qt5Widgets \
            -DQt5Xml_DIR=${QT_ROOT}/lib/cmake/Qt5Xml \
            -DQt5Network_DIR=${QT_ROOT}/lib/cmake/Qt5Network \
            -DQt5Multimedia_DIR=${QT_ROOT}/lib/cmake/Qt5Multimedia \
            -DQt5Sql_DIR=${QT_ROOT}/lib/cmake/Qt5Sql \
            -DQt5LinguistTools_DIR=${QT_ROOT}/lib/cmake/Qt5LinguistTools \
            -DSeetaFace_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaNet_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceDetector_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceLandmarker_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceRecognizer_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceTracker_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DANDROID_PLATFORM=${ANDROID_API} -DANDROID_ABI="${BUILD_ARCH}" \
            -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake 
    else
	    cmake -G"${GENERATORS}" ${SOURCE_DIR} ${CONFIG_PARA} \
            -DCMAKE_INSTALL_PREFIX=`pwd`/install \
            -DCMAKE_VERBOSE=ON \
            -DCMAKE_BUILD_TYPE=Release \
            -DQt5_DIR=${QT_ROOT}/lib/cmake/Qt5 \
            -DSeetaFace_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaNet_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceDetector_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceLandmarker_DIR=${SeetaFace2_DIR}/lib/cmake \
            -DSeetaFaceRecognizer_DIR=${SeetaFace2_DIR}/lib/cmake 
    fi
    cmake --build . --config Release --target install -- ${RABBIT_MAKE_JOB_PARA}
    if [ "${BUILD_TARGERT}" = "android" ]; then
        cmake --build . --target APK  
    fi
fi

if [ "${BUILD_TARGERT}" = "windows_msvc" ]; then
    if [ "${BUILD_ARCH}" = "x86" ]; then
        cp /C/OpenSSL-Win32/bin/libeay32.dll install/bin
        cp /C/OpenSSL-Win32/bin/ssleay32.dll install/bin
    elif [ "${BUILD_ARCH}" = "x64" ]; then
        cp /C/OpenSSL-Win64/bin/libeay32.dll install/bin
        cp /C/OpenSSL-Win64/bin/ssleay32.dll install/bin
    fi
    
    if [ -z "${STATIC}" ]; then
        "/C/Program Files (x86)/NSIS/makensis.exe" "Install.nsi"
        MD5=`md5sum FaceRecognizer-Setup-*.exe|awk '{print $1}'`
        echo "MD5:${MD5}"
        install/bin/FaceRecognizerApp.exe -f "`pwd`/update_windows.xml" --md5 ${MD5}
        
        cat update_windows.xml
    fi
fi

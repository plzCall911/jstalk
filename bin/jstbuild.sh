#!/bin/bash

# there's a lot of gus specific stuff in here.

startDate=`/bin/date`
revision=""
upload=1
ql=1
appStoreFlags=""
archFlags=""
appStore=0

while [ "$#" -gt 0 ]
do
    case "$1" in
        --store|-s)
                appStore=1
                upload=0
                appStoreFlags="-DMAC_APP_STORE"
                break
                
        --revision|-r)
                revision="-r $2"
                upload=0
                break
                ;;
        --noupload|-n)
                upload=0
                break
                ;;
        --echo|-e)
                echoversion="$2"
                break
                ;;
        *)
                echo "$CMDNAME: invalid option: $1" 1>&2
                exit 1
                ;;
    esac
    shift
done


if [ "$echoversion" != "" ]; then
    version=$echoversion
    
    # todo
    
    exit
fi


xcodebuild=/Developer/usr/bin/xcodebuild


buildDate=`/bin/date +"%Y.%m.%d.%H"`

if [ ! -d  ~/cvsbuilds ]; then
    mkdir ~/cvsbuilds
fi

echo cleaning.
rm -rf ~/cvsbuilds/JSTalk*
rm -rf /tmp/jstalk

cd /tmp

source ~/.bash_profile

echo "doing remote checkout ($revision) upload($upload)"
git clone git://github.com/ccgus/jstalk.git

cd /tmp/jstalk

#git clone http://github.com/parmanoir/jscocoa.git jscocoa
#git submodule init && git submodule update

v=`date "+%s"`

echo setting build id
sed -e "s/BUILDID/$v/g"  res/Info.plist > res/Info.plist.tmp
mv res/Info.plist.tmp res/Info.plist


function buildTarget {
    
    echo Building "$1"
    
    $xcodebuild -target "$1" -configuration Release OBJROOT=/tmp/jstalk/build SYMROOT=/tmp/jstalk/build OTHER_CFLAGS="$appStoreFlags"
    
    if [ $? != 0 ]; then
        echo "****** Bad build for $1 ********"
        say "Bad build for $1"
        exit
    fi
}


buildTarget "JSTalk Framework"
buildTarget "jstalk command line"
buildTarget "JSTalkRunner"
buildTarget "JSTalk Editor"




cd /tmp/jstalk/plugins/acornplugin
$xcodebuild -configuration Release OBJROOT=/tmp/jstalk/build SYMROOT=/tmp/jstalk/build OTHER_CFLAGS=""
if [ $? != 0 ]; then
    echo "****** Bad build for acorn plugin ********"
    exit
fi

cd /tmp/jstalk/plugins/voodoopadplugin
$xcodebuild -configuration Release OBJROOT=/tmp/jstalk/build SYMROOT=/tmp/jstalk/build OTHER_CFLAGS=""
if [ $? != 0 ]; then
    echo "****** Bad build for vp plugin ********"
    exit
fi


cd /tmp/jstalk/plugins/sqlite-fmdb-jstplugin
$xcodebuild -configuration Release OBJROOT=/tmp/jstalk/build SYMROOT=/tmp/jstalk/build OTHER_CFLAGS="" -target fmdbextra
if [ $? != 0 ]; then
    echo "****** Bad build for fmdb extra ********"
    exit
fi


cd /tmp/jstalk/plugins/imagetools
$xcodebuild -configuration Release OBJROOT=/tmp/jstalk/build SYMROOT=/tmp/jstalk/build OTHER_CFLAGS=""
if [ $? != 0 ]; then
    echo "****** Bad build for Image Tools ********"
    exit
fi

cd /tmp/jstalk/automator/
$xcodebuild -configuration Release OBJROOT=/tmp/jstalk/build SYMROOT=/tmp/jstalk/build OTHER_CFLAGS="" -target JSTAutomator
if [ $? != 0 ]; then
    echo "****** Bad build for automator action ********"
    exit
fi

mkdir -p /tmp/jstalk/build/Release/JSTalk\ Editor.app/Contents/Library/Automator
mv /tmp/jstalk/build/Release/JSTalk.action /tmp/jstalk/build/Release/JSTalk\ Editor.app/Contents/Library/Automator/.

if [ ! -d  ~/cvsbuilds ]; then
    mkdir ~/cvsbuilds
fi

cd /tmp/jstalk/build/Release/

mkdir JSTalkFoo

mv jstalk JSTalkFoo/.
mv "JSTalk Editor.app" JSTalkFoo/.

# I do a cp here, since I rely on this framework being here for other builds...
cp -R JSTalk.framework JSTalkFoo/.
cp -R /tmp/jstalk/README.txt JSTalkFoo/.
cp -R /tmp/jstalk/example_scripts JSTalkFoo/examples
cp -R /tmp/jstalk/plugins/sqlite-fmdb-jstplugin/fmdb.jstalk JSTalkFoo/examples/.

mkdir JSTalkFoo/plugins
mkdir -p JSTalkFoo/JSTalk\ Editor.app/Contents/PlugIns

cp -r JSTalk.acplugin       JSTalkFoo/plugins/.
cp -r JSTalk.vpplugin       JSTalkFoo/plugins/.
cp -r FMDB.jstplugin        JSTalkFoo/JSTalk\ Editor.app/Contents/PlugIns/.
cp -r ImageTools.jstplugin  JSTalkFoo/JSTalk\ Editor.app/Contents/PlugIns/.



mv /tmp/jstalk/plugins/proxitask/JSTalkProxiTask.bundle JSTalkFoo/plugins/.

cp /tmp/jstalk/plugins/README.txt JSTalkFoo/plugins/.

mv JSTalkFoo JSTalk


if [ $appStore = 1 ]; then
        
    productbuild --product /tmp/jstalk/resources/jstalk_product_definition.plist --component JSTalk.app /Applications --sign '3rd Party Mac Developer Installer: Flying Meat Inc.' JSTalk.pkg
    
    cp JSTalk.pkg $v-JSTalk.pkg
    
    open .
    
    exit
fi









ditto -c -k --sequesterRsrc --keepParent JSTalk JSTalk.zip

rm -rf JSTalk

mv JSTalk.zip ~/cvsbuilds/.

cd ~/cvsbuilds/

cp JSTalk.zip $v-JSTalk.zip


if [ $upload == 1 ]; then
    echo uploading to server...
    
    #downloadDir=latest
    
    scp ~/cvsbuilds/JSTalk.zip gus@elvis.mu.org:~/jstalk/download/JSTalkPreview.zip
    #scp /tmp/jstalk/res/jstalkupdate.xml gus@elvis.mu.org:~/fm/download/$downloadDir/.
    #scp /tmp/jstalk/res/shortnotes.html gus@elvis:~/fm/download/$downloadDir/jstalkshortnotes.html
fi

say "done building"

endDate=`/bin/date`
echo Start: $startDate
echo End:   $endDate

echo "(That was version $v)"

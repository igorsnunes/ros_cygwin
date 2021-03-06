#!/bin/bash
CYGWIN_MIRROR="--mirror http://cygwin.mirror.gtcomm.net/"
ROS_WORKSPACE=/opt/ros
ROS_DEPS=/opt/rosdeps
ROS_DISTRO=indigo
export SOURCEFORGE_MIRROR=downloads.sourceforge.net

SCRIPT_ROOT=$(dirname $(readlink -f $0))

provide_prerequisite () {	#Args: package name, [check command = $1 --version]
	testcmd=$2
	if [ -z "$testcmd" ]
	then
		testcmd="test -e /usr/bin/$1"
	fi
	
	$testcmd >/dev/null 2>&1 && return 0
	apt-cyg $CYGWIN_MIRROR install $1 || (echo "$1 installation failed. Run 'apt-cyg install $1' to install it manually."; return 1)
	$testcmd >/dev/null 2>&1 && return 0
	echo $testcmd
	echo "$1 cannot be found despite successful installation. Please investigate.";
	return 1
}

provide_pip_prerequisite () {	#Args: package name, [check command = test -f /usr/bin/$1]
	testcmd=$2
	if [ -z "$testcmd" ]
	then
		testcmd="test -f /usr/bin/$1"
	fi
	
	$testcmd >/dev/null 2>&1 && return 0
	pip install -U $1 || (echo "$1 installation failed. Run 'pip install -U $1' to install it manually."; return 1)
	$testcmd >/dev/null 2>&1 && return 0
	echo $testcmd
	echo "$1 cannot be found despite successful installation. Please investigate.";
	return 1
}

provide_pip_library() {
	provide_pip_prerequisite $1 "test -d /lib/python2.7/site-packages/$1*"
}

install_pip () {
	wget https://bootstrap.pypa.io/get-pip.py || return 1
	python get-pip.py || (rm get-pip.py ; return 1)
	rm get-pip.py
	return 0;
}

patch_single_module() {	#Args: <module name>
	test -e $SCRIPT_ROOT/patches/ros/$ROS_DISTRO/$1.patch || test -e $SCRIPT_ROOT/patches/ros/$1.patch || return 0	#No patch avilable
	test -e $ROS_WORKSPACE/src/$1/$1.patch && return 0	#Already patched
	echo "Patching $1..."
	if [ -e $SCRIPT_ROOT/patches/ros/$ROS_DISTRO/$1.patch ]; then
		PATCH_FILE=$SCRIPT_ROOT/patches/ros/$ROS_DISTRO/$1.patch
	else
		PATCH_FILE=$SCRIPT_ROOT/patches/ros/$1.patch
	fi

	patch -d $ROS_WORKSPACE/src/$1 -p2 < $PATCH_FILE || return 1
	cp $PATCH_FILE $ROS_WORKSPACE/src/$1/$1.patch	#Just to indicate that this has already been patched
}

patch_system_file() { #Args: file, patch file
	test -e $1.patch && return 0	#Already patched
	patch $1 < $2 || return 1
	cp $2 $1.patch
}

add_package_to_src() { #Args: subdir, URL
	test -d src/$1 && echo "$1 already checked out" && return 0
	test -d $1 || git clone $2 src/$1 || return 1
}

mkdir -m 777 -p $ROS_WORKSPACE $ROS_DEPS

echo "Checking tool prerequisites..."
for pkg in python make cmake gdb git patch unzip pkg-config; do
	provide_prerequisite $pkg || exit 1
done
provide_prerequisite gcc-g++ "/usr/bin/g++ --version" || exit 1
provide_prerequisite diffutils "/usr/bin/cmp --version" || exit 1
provide_prerequisite libtool "libtool --version" || exit 1
provide_prerequisite fluid "test -f /usr/bin/fluid.exe" || exit 1
provide_prerequisite graphviz "test -f /usr/bin/dot.exe" || exit 1
provide_prerequisite oxygen-icons "test -d /usr/share/icons/oxygen" || exit 1
provide_prerequisite hicolor-icon-theme "test -d /usr/share/icons/hicolor" || exit 1
provide_prerequisite gnome-icon-theme "test -d /usr/share/icons/gnome" || exit 1

echo "Checking library prerequisites..."
provide_prerequisite libpoco-devel "test -f /lib/libPocoData.dll.a" || exit 1
provide_prerequisite libboost-devel "test -f /lib/libboost_system.dll.a" || exit 1
provide_prerequisite libboost_python-devel "test -f /lib/libboost_python.dll.a" || exit 1
provide_prerequisite libGLU-devel "test -f /lib/libGL.dll.a" || exit 1
provide_prerequisite libgtk2.0-devel "test -f /lib/libgtk-x11-2.0.dll.a" || exit 1
for lib in curl jpeg fltk X11 Xext freetype xml2 qhull SDL SDL_image ffi; do
	provide_prerequisite lib$lib-devel "test -f /lib/lib$lib.dll.a" || exit 1
done

echo "Checking python tool prerequisites..."
test -f /usr/bin/pip || (install_pip || exit 1)
for pkg in rosdep rosinstall_generator wstool rosinstall; do
	provide_pip_prerequisite $pkg || exit 1
done

echo "Checking python library prerequisites..."
for pkg in empy; do
	provide_pip_library $pkg || exit 1
done

provide_pip_prerequisite numpy "test -d /lib/python2.7/site-packages/numpy"
provide_pip_prerequisite pyparsing "test -f /lib/python2.7/site-packages/pyparsing.py"
provide_pip_prerequisite pydot "test -f /lib/python2.7/site-packages/pydot.py"
provide_pip_prerequisite pyqtgraph "test -d /lib/python2.7/site-packages/pyqtgraph"
provide_pip_prerequisite Pillow "test -d /lib/python2.7/site-packages/PIL"
provide_pip_prerequisite cairocffi "test -d /lib/python2.7/site-packages/cairocffi"


if [ -z $NUMBER_OF_PROCESSORS ]; then
	echo "Will build external libraries in one thread"
else
	echo "Will build external libraries in one $NUMBER_OF_PROCESSORS threads"
	export PARALLEL_BUILD_FLAGS=-j$NUMBER_OF_PROCESSORS
fi

export PATH=$PATH:$QTDIR/lib

echo "Patching system files..."
patch_system_file /usr/include/boost/thread/pthread/recursive_mutex.hpp $SCRIPT_ROOT/patches/boost.patch
patch_system_file /usr/include/ctype.h $SCRIPT_ROOT/patches/ctype.patch
patch_system_file /usr/include/sys/features.h $SCRIPT_ROOT/patches/features.patch

echo "Checking buildable external packages..."
for pkg in `ls -1 $SCRIPT_ROOT/install_helpers/*.sh`; do
	bash $pkg $ROS_DEPS || exit 1
done

cd $ROS_WORKSPACE || exit 1
test -e $ROS_DISTRO-desktop-full-wet.rosinstall || (echo "Generating package list..."; rosinstall_generator desktop_full --rosdistro $ROS_DISTRO --deps --wet-only --tar > $ROS_DISTRO-desktop-full-wet.rosinstall)
test -e src/.rosinstall || (echo "Downloading package sources..."; wstool init -j8 src $ROS_DISTRO-desktop-full-wet.rosinstall)

if [ -d src/navigation_msgs ] && [ ! -d src/navigation_msgs/move_base_msgs ]; then
	rm -rf src/navigation_msgs
fi

add_package_to_src navigation https://github.com/ros-planning/navigation.git || exit 1
add_package_to_src navigation_msgs https://github.com/ros-planning/navigation_msgs.git || exit 1
add_package_to_src openslam_gmapping https://github.com/ros-perception/openslam_gmapping.git || exit 1
add_package_to_src slam_gmapping https://github.com/ros-perception/slam_gmapping.git  || exit 1

echo "Patching ROS sources..."
for dir in `ls -1 $ROS_WORKSPACE/src`; do
	patch_single_module $dir || exit 1
done

test -e src/map_msgs && rm -rf src/map_msgs

for pkg in gazebo_ros_pkgs/gazebo_msgs gazebo_ros_pkgs/gazebo_plugins gazebo_ros_pkgs/gazebo_ros gazebo_ros_pkgs/gazebo_ros_pkgs image_transport_plugins/theora_image_transport; do
	echo "*** $pkg IS EXCLUDED FROM BUILD ***"
	test -e src/$pkg/package.xml && mv src/$pkg/package.xml src/$pkg/package.disabled
done

echo "Building ROS..."
export PYTHONPATH=$PYTHONPATH:$ROS_WORKSPACE/install_isolated/lib/python2.7/site-packages
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/local/lib/pkgconfig
src/catkin/bin/catkin_make_isolated --install -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_SHARED_LIBS=1 -DCMAKE_LEGACY_CYGWIN_WIN32=0 -DCATKIN_ENABLE_TESTING=0 $* || exit 1

chmod 777 $ROS_WORKSPACE/install_isolated/lib/python2.7/site-packages/qt_gui_cpp/libqt_gui_cpp_sip.dll

cp $SCRIPT_ROOT/linkexes.pl .
perl linkexes.pl
test -d /usr/share/icons/Tango || (echo "!!!! Tango icons not found !!!!" ; echo "Please copy the /usr/share/icons/Tango folder from a Linux machine with KDE")
echo "ROS build complete."
echo "Do not forget to rebase it by closing ALL cygwin windows and running rebase_ros.bat"
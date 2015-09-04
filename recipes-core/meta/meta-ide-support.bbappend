##
## This append modifies the meta-ide-support recipe to generate a
## cross-development SDK.
## This modifies the original meta-ide-support recipe to generate a
## cross-development SDK that:
##    - Can be installed by app developers on any machine, irrespective of whether
##      they have access to the original bitbake tree where the SDK was generated
##    - Contains the sysroots needed for cross-development
##    - Contains the external cross toolchain used to develop the distro
##
## It changes the recipe as follows:
##    - Modifies the do_populate_ide_support to not call
##      toolchain_create_tree_env_script from toolchain-scripts.bbclass.
##    - Instead, it starts by calling update_installer_script that updates a script that
##      installs the SDK at a desired location. (See Installer Script below)
##    - Then it calls our own create_environment_script function
##       - followed by our own create_toolchain_shared_env_script
##       - Both these functions take similar functions from the original class, but
##         set enviroment variables to paths that are not absolute. They generate
##         paths relative to $SDK_DIR, which makes it easy to move the SDK and just
##         set the SDK_DIR variable at the top of the environment-setup-<target> file
##    - Then it calls create_package which creates a tarball that includes:
##       - The sysroots
##       - The environment-setup-<target> file
##       - An installer script
##       - An example app
##
## Installer Script:
## =========
## The installer script starts off as a file with patterns in it. The function
## update_installer_script replaces patterns with recipe variables,
## e.g. %PATTERN_GCC_URL% with ${QRL_GCC_URL}.
##
## The script itself takes as argument the target location where to install
## the SDK, and does the following:
##    - Installs the sysroots at the target location
##    - Installs the example app at the target location
##    - Modifies the environment-setup-<target> script to use this location
## 

# The OECORE variable isn't available to this recipe, so we have to compute it here   
QRL_OECORE = "${@os.path.dirname(bb.data.getVar('TOPDIR', d,1))}"

# The name used for the installer script generated by this recipe
QRL_SDK_INSTALL_SCRIPT ?= "qrlSDKInstaller.sh"

# The name used for the tarball  generated by this recipe
QRL_SDK_TARBALL_NAME ?= "qrlSDK.tgz"

# The name used for the sysroots tarball
QRL_SDK_SYSROOTS_TARBALL_NAME ?= "qrlSysroots.tgz"

QRL_GCC_URL ?= "http://releases.linaro.org/13.08/components/toolchain/binaries"

FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += "file://README"
SRC_URI += "file://hello.c"
SRC_URI += "file://Makefile"
SRC_URI += "file://${QRL_SDK_INSTALL_SCRIPT}"

##
## Ugh. We need to find a better way to copy sample app files from the
## "files" location to a subdir under S. Enumerating each file can get tedious
## if the sample app(s) grow
## 
do_unpack_append() {
    import shutil
    import os
    src = d.getVar('WORKDIR', True)
    dest = d.getVar('S', True)
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.mkdir(dest)
    shutil.copy(src+"/${QRL_SDK_INSTALL_SCRIPT}", dest)
    shutil.copy(src+"/README", dest)
    dest = dest+'/sample'
    os.mkdir(dest)
    shutil.copy(src+"/hello.c", dest)
    shutil.copy(src+"/Makefile", dest)
}

##
## Function used to normalize the PATH variable. It removes absolute paths
## referring to the build tree, and makes them point to $SDK_DIR variable
## 
normalizeWholePath () {
   path=$1
   # Replace all references to build tree with SDK_DIR
   path=`echo ${path} | awk 'gsub ( "${TMPDIR}", "$\{SDK_DIR\}" )'`
   path=`echo ${path} | awk 'gsub ( "${QRL_OECORE}", "$\{SDK_DIR\}" )'`
   path=`echo ${path} | awk 'gsub ( "\\\\${SDK_DIR}/scripts:", "" )'`
   path=`echo ${path} | awk 'gsub ( "\\\\${SDK_DIR}/bitbake/bin:", "" )'`
   path=`echo ${path} | awk 'gsub ( "\\\\${SDK_DIR}/build/..", "$\{SDK_DIR\}" )'`
   # echo ${path} | tr ':' '\n'
   echo ${path}
}

##
## Function used to replace $TMPDIR with $SDK_DIR
## 
normalizePath_TMPDIR () {
   path=$1
   path=`echo ${path} | awk 'gsub ( "${TMPDIR}", "$\{SDK_DIR\}" )'`
   echo ${path}
}

##
## Function used to replace refs. to build tree with $SDK_DIR, specifically for
## XXXFLAG variables, e.g. CC_FLAGS
## 
normalizePath_FLAGS () {
   path=$1
   # Replace all references to build tree with SDK_DIR
   path=`echo ${path} | awk 'gsub ( "${QRL_OECORE}/build/..", "$\{SDK_DIR\}" )'`
   echo ${path}
}

create_environment_script () {
	script=${S}/environment-setup-${REAL_MULTIMACH_TARGET_SYS}
	rm -f $script
	touch $script
	# For some reason I need to call these functions here, else they aren't
	# available inside the echo commands below
	x=$(normalizeWholePath ${PATH})
        x=$(normalizePath_TMPDIR ${PKG_CONFIG_SYSROOT_DIR})
	
	echo 'SDK_DIR=' >> $script
	echo "export PATH=\"$(normalizeWholePath ${PATH})\"" >> $script
	echo "export PKG_CONFIG_SYSROOT_DIR=\"$(normalizePath_TMPDIR ${PKG_CONFIG_SYSROOT_DIR})\"" >> $script
	echo "export PKG_CONFIG_PATH=\"$(normalizePath_TMPDIR ${PKG_CONFIG_PATH})\"" >> $script
#	echo 'export CONFIG_SITE="${@siteinfo_get_files(d)}"' >> $script
	echo "export SDKTARGETSYSROOT=\"$(normalizePath_TMPDIR ${STAGING_DIR_TARGET})\"" >> $script
	echo "export OECORE_NATIVE_SYSROOT=\"$(normalizePath_TMPDIR ${STAGING_DIR_NATIVE})\"" >> $script
	echo "export OECORE_TARGET_SYSROOT=\"$(normalizePath_TMPDIR ${STAGING_DIR_TARGET})\"" >> $script
	echo "export OECORE_ACLOCAL_OPTS=\"-I $(normalizePath_TMPDIR ${STAGING_DIR_NATIVE})/usr/share/aclocal\"" >> $script

	create_toolchain_shared_env_script
}

create_toolchain_shared_env_script () {
	echo 'export CC="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export CXX="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH} --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export CPP="${TARGET_PREFIX}gcc -E ${TARGET_CC_ARCH} --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export AS="${TARGET_PREFIX}as ${TARGET_AS_ARCH}"' >> $script
	echo 'export LD="${TARGET_PREFIX}ld ${TARGET_LD_ARCH} --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export GDB=${TARGET_PREFIX}gdb' >> $script
	echo 'export STRIP=${TARGET_PREFIX}strip' >> $script
	echo 'export RANLIB=${TARGET_PREFIX}ranlib' >> $script
	echo 'export OBJCOPY=${TARGET_PREFIX}objcopy' >> $script
	echo 'export OBJDUMP=${TARGET_PREFIX}objdump' >> $script
	echo 'export AR=${TARGET_PREFIX}ar' >> $script
	echo 'export NM=${TARGET_PREFIX}nm' >> $script
	echo 'export M4=m4' >> $script
	echo 'export TARGET_PREFIX=${TARGET_PREFIX}' >> $script
	echo 'export CONFIGURE_FLAGS="--target=${TARGET_SYS} --host=${TARGET_SYS} --build=${SDK_ARCH}-linux --with-libtool-sysroot=$SDKTARGETSYSROOT"' >> $script
        # Again, need to call this out here, before I can use in echo further down
        x=$(normalizePath_FLAGS ${TARGET_CFLAGS})
 	echo "export CFLAGS=\"$(normalizePath_FLAGS ${TARGET_CFLAGS})\"" >> $script
	echo "export CXXFLAGS=\"$(normalizePath_FLAGS ${TARGET_CXXFLAGS})\"" >> $script
	echo "export LDFLAGS=\"$(normalizePath_FLAGS ${TARGET_LDFLAGS})\"" >> $script
	echo "export CPPFLAGS=\"$(normalizePath_FLAGS ${TARGET_CPPFLAGS})\"" >> $script
	echo 'export OECORE_DISTRO_VERSION="${DISTRO_VERSION}"' >> $script
	echo 'export OECORE_SDK_VERSION="${SDK_VERSION}"' >> $script
	echo 'export ARCH=${ARCH}' >> $script
	echo 'export CROSS_COMPILE=${TARGET_PREFIX}' >> $script
}

##
## Creates the installer script
## 
update_installer_script () {
	script=${S}/${QRL_SDK_INSTALL_SCRIPT}
        envFile=environment-setup-${REAL_MULTIMACH_TARGET_SYS}
        tc=`basename ${EXTERNAL_TOOLCHAIN}`
        sed -i "s|%PATTERN_SDK_DIR%|${SDK_DIR}|" $script
        sed -i "s|%PATTERN_ENV_FILE%|${envFile}|" $script
        sed -i "s|%PATTERN_SYSROOTS_TGZ%|${QRL_SDK_SYSROOTS_TARBALL_NAME}|" $script
        sed -i "s|%PATTERN_GCC%|${tc}|" $script
        sed -i "s|%PATTERN_GCC_URL%|${QRL_GCC_URL}|" $script
	chmod +x $script

}

#########################################
create_package () {
        sleep 2 # Delay to allow sysroots dir to settle
        tar -zcf ${S}/${QRL_SDK_SYSROOTS_TARBALL_NAME} -C ${TMPDIR} sysroots 
        tar -zcf ${S}/${QRL_SDK_TARBALL_NAME} -C ${S} README ${QRL_SDK_SYSROOTS_TARBALL_NAME} ${QRL_SDK_INSTALL_SCRIPT} environment-setup-${REAL_MULTIMACH_TARGET_SYS} sample
        deployDir="${DEPLOY_DIR}/sdk"
        mkdir -p $deployDir
        mv ${S}/${QRL_SDK_TARBALL_NAME} $deployDir
        rm ${S}/${QRL_SDK_SYSROOTS_TARBALL_NAME}
}

#########################################
do_populate_ide_support () {
        update_installer_script
        create_environment_script
        create_package
}

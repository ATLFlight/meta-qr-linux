LIC_FILES_CHKSUM = "file://${COREBASE}/LICENSE;md5=3f40d7994397109285ec7b81fdeb3b58 \
                    file://${COREBASE}/meta-qr-linux/COPYING;md5=af4568eb99af15f8fbea8230e6762581"


# Images are generally built explicitly, do not need to be part of world.
EXCLUDE_FROM_WORLD = "1"
do_rootfs[dirs] = "${TOPDIR} ${WORKDIR}/intercept_scripts"
do_rootfs[lockfiles] += "${IMAGE_ROOTFS}.lock"
do_rootfs[cleandirs] += "${S} ${WORKDIR}/intercept_scripts"
do_rootfs[deptask] += "do_package_write_deb"

# Must call real_do_rootfs() from inside here, rather than as a separate
# task, so that we have a single fakeroot context for the whole process.
do_rootfs[umask] = "022"

fakeroot do_rootfs() {
	if [ -e ${IMAGE_ROOTFS} ]; then
	    rm -rf ${IMAGE_ROOTFS}
	fi
	if [ -e ${WORKDIR}/${MACHINE} ]; then
	    rm -rf ${WORKDIR}/${MACHINE}
	fi
	install -d ${IMAGE_ROOTFS}
	install -d ${WORKDIR}/${MACHINE}

	# Do any preprocessing for multistrap
	${MULTISTRAP_PREPROCESS_COMMAND}

	# Construct the user space.
	APT_CONFIG=${WORKDIR}/apt.conf /usr/sbin/multistrap -f ${WORKDIR}/multistrap.conf -d ${IMAGE_ROOTFS} --tidy-up --source-dir ${WORKDIR}/${MACHINE}

	# Create the image directory
	mkdir -p ${DEPLOY_DIR_IMAGE}

	${IMAGE_PREPROCESS_COMMAND}

	${@get_imagecmds(d)}

	${IMAGE_POSTPROCESS_COMMAND}
	
	${MACHINE_POSTPROCESS_COMMAND}
}

do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
do_populate_sysroot[noexec] = "1"
do_package[noexec] = "1"
do_packagedata[noexec] = "1"
do_package_write_ipk[noexec] = "1"
do_package_write_deb[noexec] = "1"
do_package_write_rpm[noexec] = "1"

addtask rootfs before do_build

DEPENDS += "e2fsprogs-native"

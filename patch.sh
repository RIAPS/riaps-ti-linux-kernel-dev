#!/bin/bash -e
#
# Copyright (c) 2009-2019 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Split out, so build_kernel.sh and build_deb.sh can share..

shopt -s nullglob

. ${DIR}/version.sh
if [ -f ${DIR}/system.sh ] ; then
	. ${DIR}/system.sh
fi
git_bin=$(which git)
#git hard requirements:
#git: --no-edit

git="${git_bin} am"
#git_patchset="git://git.ti.com/ti-linux-kernel/ti-linux-kernel.git"
git_patchset="https://github.com/RobertCNelson/ti-linux-kernel.git"
#git_opts

if [ "${RUN_BISECT}" ] ; then
	git="${git_bin} apply"
fi

echo "Starting patch.sh"

git_add () {
	${git_bin} add .
	${git_bin} commit -a -m 'testing patchset'
}

start_cleanup () {
	git="${git_bin} am --whitespace=fix"
}

cleanup () {
	if [ "${number}" ] ; then
		if [ "x${wdir}" = "x" ] ; then
			${git_bin} format-patch -${number} -o ${DIR}/patches/
		else
			if [ ! -d ${DIR}/patches/${wdir}/ ] ; then
				mkdir -p ${DIR}/patches/${wdir}/
			fi
			${git_bin} format-patch -${number} -o ${DIR}/patches/${wdir}/
			unset wdir
		fi
	fi
	exit 2
}

dir () {
	wdir="$1"
	if [ -d "${DIR}/patches/$wdir" ]; then
		echo "dir: $wdir"

		if [ "x${regenerate}" = "xenable" ] ; then
			start_cleanup
		fi

		number=
		for p in "${DIR}/patches/$wdir/"*.patch; do
			${git} "$p"
			number=$(( $number + 1 ))
		done

		if [ "x${regenerate}" = "xenable" ] ; then
			cleanup
		fi
	fi
	unset wdir
}

cherrypick () {
	if [ ! -d ../patches/${cherrypick_dir} ] ; then
		mkdir -p ../patches/${cherrypick_dir}
	fi
	${git_bin} format-patch -1 ${SHA} --start-number ${num} -o ../patches/${cherrypick_dir}
	num=$(($num+1))
}

external_git () {
	git_tag="ti-linux-${KERNEL_REL}.y"
	echo "pulling: [${git_patchset} ${git_tag}]"
	${git_bin} pull --no-edit ${git_patchset} ${git_tag}
	top_of_branch=$(${git_bin} describe)
	if [ ! "x${ti_git_post}" = "x" ] ; then
		${git_bin} checkout master -f
		test_for_branch=$(${git_bin} branch --list "v${KERNEL_TAG}${BUILD}")
		if [ "x${test_for_branch}" != "x" ] ; then
			${git_bin} branch "v${KERNEL_TAG}${BUILD}" -D
		fi
		${git_bin} checkout ${ti_git_post} -b v${KERNEL_TAG}${BUILD} -f
		current_git=$(${git_bin} describe)
		echo "${current_git}"

		if [ ! "x${top_of_branch}" = "x${current_git}" ] ; then
			echo "INFO: external git repo has updates..."
		fi
	else
		echo "${top_of_branch}"
	fi
}

aufs_fail () {
	echo "aufs failed"
	exit 2
}

aufs () {
	aufs_prefix="aufs4-"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		KERNEL_REL=4.14.73+
		wget https://raw.githubusercontent.com/sfjro/${aufs_prefix}standalone/aufs${KERNEL_REL}/${aufs_prefix}kbuild.patch
		patch -p1 < ${aufs_prefix}kbuild.patch || aufs_fail
		rm -rf ${aufs_prefix}kbuild.patch
		${git_bin} add .
		${git_bin} commit -a -m 'merge: aufs-kbuild' -s

		wget https://raw.githubusercontent.com/sfjro/${aufs_prefix}standalone/aufs${KERNEL_REL}/${aufs_prefix}base.patch
		patch -p1 < ${aufs_prefix}base.patch || aufs_fail
		rm -rf ${aufs_prefix}base.patch
		${git_bin} add .
		${git_bin} commit -a -m 'merge: aufs-base' -s

		wget https://raw.githubusercontent.com/sfjro/${aufs_prefix}standalone/aufs${KERNEL_REL}/${aufs_prefix}mmap.patch
		patch -p1 < ${aufs_prefix}mmap.patch || aufs_fail
		rm -rf ${aufs_prefix}mmap.patch
		${git_bin} add .
		${git_bin} commit -a -m 'merge: aufs-mmap' -s

		wget https://raw.githubusercontent.com/sfjro/${aufs_prefix}standalone/aufs${KERNEL_REL}/${aufs_prefix}standalone.patch
		patch -p1 < ${aufs_prefix}standalone.patch || aufs_fail
		rm -rf ${aufs_prefix}standalone.patch
		${git_bin} add .
		${git_bin} commit -a -m 'merge: aufs-standalone' -s

		${git_bin} format-patch -4 -o ../patches/aufs/

		cd ../
		if [ ! -d ./${aufs_prefix}standalone ] ; then
			${git_bin} clone -b aufs${KERNEL_REL} https://github.com/sfjro/${aufs_prefix}standalone --depth=1
		else
			rm -rf ./${aufs_prefix}standalone || true
			${git_bin} clone -b aufs${KERNEL_REL} https://github.com/sfjro/${aufs_prefix}standalone --depth=1
		fi
		cd ./KERNEL/
		KERNEL_REL=4.14

		cp -v ../${aufs_prefix}standalone/Documentation/ABI/testing/*aufs ./Documentation/ABI/testing/
		mkdir -p ./Documentation/filesystems/aufs/
		cp -rv ../${aufs_prefix}standalone/Documentation/filesystems/aufs/* ./Documentation/filesystems/aufs/
		mkdir -p ./fs/aufs/
		cp -v ../${aufs_prefix}standalone/fs/aufs/* ./fs/aufs/
		cp -v ../${aufs_prefix}standalone/include/uapi/linux/aufs_type.h ./include/uapi/linux/

		${git_bin} add .
		${git_bin} commit -a -m 'merge: aufs' -s
		${git_bin} format-patch -5 -o ../patches/aufs/

		rm -rf ../${aufs_prefix}standalone/ || true

		${git_bin} reset --hard HEAD~5

		start_cleanup

		${git} "${DIR}/patches/aufs/0001-merge-aufs-kbuild.patch"
		${git} "${DIR}/patches/aufs/0002-merge-aufs-base.patch"
		${git} "${DIR}/patches/aufs/0003-merge-aufs-mmap.patch"
		${git} "${DIR}/patches/aufs/0004-merge-aufs-standalone.patch"
		${git} "${DIR}/patches/aufs/0005-merge-aufs.patch"

		wdir="aufs"
		number=5
		cleanup
	fi

	dir 'aufs'
}

rt_cleanup () {
	echo "rt: needs fixup"
	exit 2
}

rt () {
	rt_patch="${KERNEL_REL}${kernel_rt}"

	#v4.14.x
	#${git_bin} revert --no-edit xyz

	#revert this from ti's branch...
	${git_bin} revert --no-edit 2f6872da466b6f35b3c0a94aa01629da7ae9b72b

	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		wget -c https://www.kernel.org/pub/linux/kernel/projects/rt/${KERNEL_REL}/older/patch-${rt_patch}.patch.xz
		xzcat patch-${rt_patch}.patch.xz | patch -p1 || rt_cleanup
		rm -f patch-${rt_patch}.patch.xz
		rm -f localversion-rt
		${git_bin} add .
		${git_bin} commit -a -m 'merge: CONFIG_PREEMPT_RT Patch Set' -s
		${git_bin} format-patch -1 -o ../patches/rt/

		exit 2
	fi

	dir 'rt'
}

backport_brcm80211 () {
	echo "dir: brcm80211"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		cd ../
		if [ ! -d ./brcm80211 ] ; then
			${git_bin} clone -b rpi-4.14.y https://github.com/raspberrypi/linux brcm80211 --depth=1 --reference ./KERNEL/
		else
			rm -rf ./brcm80211 || true
			${git_bin} clone -b rpi-4.14.y https://github.com/raspberrypi/linux brcm80211 --depth=1 --reference ./KERNEL/
		fi
		cd ./KERNEL/

		cp -rv ../brcm80211/drivers/net/wireless/broadcom/brcm80211/ ./drivers/net/wireless/broadcom/

		${git_bin} add .
		${git_bin} commit -a -m 'merge: brcm80211' -s
		${git_bin} format-patch -1 -o ../patches/brcm80211/

		rm -rf ../brcm80211/ || true

		${git_bin} reset --hard HEAD^

		start_cleanup

		${git} "${DIR}/patches/brcm80211/0001-merge-brcm80211.patch"

		wdir="brcm80211"
		number=1
		cleanup
	fi

	${git} "${DIR}/patches/brcm80211/0001-merge-brcm80211.patch"
}

wireguard_fail () {
	echo "WireGuard failed"
	exit 2
}

wireguard () {
	echo "dir: WireGuard"

	#[    3.315290] NOHZ: local_softirq_pending 242
	#[    3.319504] NOHZ: local_softirq_pending 242
	${git_bin} revert --no-edit 2d898915ccf4838c04531c51a598469e921a5eb5

	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		cd ../
		if [ ! -d ./WireGuard ] ; then
			${git_bin} clone https://git.zx2c4.com/WireGuard --depth=1
		else
			rm -rf ./WireGuard || true
			${git_bin} clone https://git.zx2c4.com/WireGuard --depth=1
		fi

		#cd ./WireGuard/
		#${git_bin}  revert --no-edit xyz
		#cd ../

		cd ./KERNEL/

		../WireGuard/contrib/kernel-tree/create-patch.sh | patch -p1 || wireguard_fail

		${git_bin} add .
		${git_bin} commit -a -m 'merge: WireGuard' -s
		${git_bin} format-patch -1 -o ../patches/WireGuard/

		rm -rf ../WireGuard/ || true

		${git_bin} reset --hard HEAD^

		start_cleanup

		${git} "${DIR}/patches/WireGuard/0001-merge-WireGuard.patch"

		wdir="WireGuard"
		number=1
		cleanup
	fi

	dir 'WireGuard'
}

ti_pm_firmware () {
	#http://git.ti.com/gitweb/?p=processor-firmware/ti-amx3-cm3-pm-firmware.git;a=shortlog;h=refs/heads/ti-v4.1.y-next
	echo "dir: drivers/ti/firmware"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then

		cd ../
		if [ ! -d ./ti-amx3-cm3-pm-firmware ] ; then
			${git_bin} clone -b ti-v4.1.y-next git://git.ti.com/processor-firmware/ti-amx3-cm3-pm-firmware.git --depth=1
		else
			rm -rf ./ti-amx3-cm3-pm-firmware || true
			${git_bin} clone -b ti-v4.1.y-next git://git.ti.com/processor-firmware/ti-amx3-cm3-pm-firmware.git --depth=1
		fi
		cd ./KERNEL/

		cp -v ../ti-amx3-cm3-pm-firmware/bin/am* ./firmware/

		${git_bin} add -f ./firmware/am*
		${git_bin} commit -a -m 'add am33x firmware' -s
		${git_bin} format-patch -1 -o ../patches/drivers/ti/firmware/

		rm -rf ../ti-amx3-cm3-pm-firmware/ || true

		${git_bin} reset --hard HEAD^

		start_cleanup

		${git} "${DIR}/patches/drivers/ti/firmware/0001-add-am33x-firmware.patch"

		wdir="drivers/ti/firmware"
		number=1
		cleanup
	fi

	${git} "${DIR}/patches/drivers/ti/firmware/0001-add-am33x-firmware.patch"
}

dtb_makefile_append_am5 () {
	sed -i -e 's:am57xx-beagle-x15.dtb \\:am57xx-beagle-x15.dtb \\\n\t'$device' \\:g' arch/arm/boot/dts/Makefile
}

dtb_makefile_append () {
	sed -i -e 's:am335x-boneblack.dtb \\:am335x-boneblack.dtb \\\n\t'$device' \\:g' arch/arm/boot/dts/Makefile
}

beagleboard_dtbs () {
	bbdtbs="v4.14.x-ti"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		cd ../
		if [ ! -d ./BeagleBoard-DeviceTrees ] ; then
			${git_bin} clone -b ${bbdtbs} https://github.com/beagleboard/BeagleBoard-DeviceTrees --depth=1
		else
			rm -rf ./BeagleBoard-DeviceTrees || true
			${git_bin} clone -b ${bbdtbs} https://github.com/beagleboard/BeagleBoard-DeviceTrees --depth=1
		fi
		cd ./KERNEL/

		cp -vr ../BeagleBoard-DeviceTrees/src/arm/* arch/arm/boot/dts/
		cp -vr ../BeagleBoard-DeviceTrees/include/dt-bindings/* ./include/dt-bindings/

		device="am335x-boneblack-uboot.dtb" ; dtb_makefile_append

		device="am335x-sancloud-bbe.dtb" ; dtb_makefile_append

		device="am335x-abbbi.dtb" ; dtb_makefile_append

		device="am335x-olimex-som.dtb" ; dtb_makefile_append

		device="am335x-boneblack-wl1835mod.dtb" ; dtb_makefile_append
		device="am335x-boneblack-bbbmini.dtb" ; dtb_makefile_append
		device="am335x-boneblack-bbb-exp-c.dtb" ; dtb_makefile_append
		device="am335x-boneblack-bbb-exp-r.dtb" ; dtb_makefile_append
		device="am335x-boneblack-audio.dtb" ; dtb_makefile_append

		device="am335x-pocketbeagle.dtb" ; dtb_makefile_append
		device="am335x-pocketbeagle-gamepup.dtb" ; dtb_makefile_append
		device="am335x-pocketbeagle-techlab.dtb" ; dtb_makefile_append

		device="am335x-boneblack-roboticscape.dtb" ; dtb_makefile_append
		device="am335x-boneblack-wireless-roboticscape.dtb" ; dtb_makefile_append

		device="am335x-bone-uboot-univ.dtb" ; dtb_makefile_append
		device="am335x-boneblack-uboot-univ.dtb" ; dtb_makefile_append
		device="am335x-bonegreen-wireless-uboot-univ.dtb" ; dtb_makefile_append
		device="am335x-sancloud-bbe-uboot.dtb" ; dtb_makefile_append
		device="am335x-sancloud-bbe-uboot-univ.dtb" ; dtb_makefile_append

		device="am57xx-evm.dtb" ; dtb_makefile_append_am5
		device="am57xx-evm-reva3.dtb" ; dtb_makefile_append_am5
		device="am57xx-beagle-x15-gssi.dtb" ; dtb_makefile_append_am5

		device="am5729-beagleboneai.dtb" ; dtb_makefile_append_am5
		device="am5729-beagleboneai-roboticscape.dtb" ; dtb_makefile_append_am5

		${git_bin} add -f arch/arm/boot/dts/
		${git_bin} add -f include/dt-bindings/
		${git_bin} commit -a -m "Add BeagleBoard.org DTBS: $bbdtbs" -m "https://github.com/beagleboard/BeagleBoard-DeviceTrees/tree/${bbdtbs}" -s
		${git_bin} format-patch -1 -o ../patches/soc/ti/beagleboard_dtbs/

		rm -rf ../BeagleBoard-DeviceTrees/ || true

		${git_bin} reset --hard HEAD^

		start_cleanup

		${git} "${DIR}/patches/soc/ti/beagleboard_dtbs/0001-Add-BeagleBoard.org-DTBS-$bbdtbs.patch"

		wdir="soc/ti/beagleboard_dtbs"
		number=1
		cleanup
	fi

	dir 'soc/ti/beagleboard_dtbs'
}

local_patch () {
	echo "dir: dir"
	${git} "${DIR}/patches/dir/0001-patch.patch"
}

external_git
aufs
#rt
#backport_brcm80211
#wireguard
ti_pm_firmware
beagleboard_dtbs
#local_patch

ipipe () {
	kernel_base="v4.14.96"
	xenomai_branch="stable/4.14.96-arm"
	echo "dir: ipipe"

	${git_bin} revert --no-edit a8aac659b9652430ccf898dd61bc6f996e3aef9d

	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		#https://gitlab.denx.de/Xenomai/ipipe-arm
		#https://gitlab.denx.de/Xenomai/ipipe-arm/tree/stable/4.14.96-arm
		${git_bin} checkout v${KERNEL_TAG}${BUILD} -f
		test_for_branch=$(${git_bin} branch --list "${xenomai_branch}")
		if [ "x${test_for_branch}" != "x" ] ; then
			${git_bin} branch "${xenomai_branch}" -D
		fi

		${git_bin} checkout ${kernel_base} -b ${xenomai_branch}

		cp -v drivers/pci/dwc/pcie-designware-host.c ../patches/ipipe/drivers_pci_dwc_pcie-designware-host.c

		cp -v drivers/pinctrl/bcm/pinctrl-bcm2835.c ../patches/ipipe/drivers_pinctrl_bcm_pinctrl-bcm2835.c

		echo "${git_bin} pull --no-edit https://gitlab.denx.de/Xenomai/ipipe-arm.git ${xenomai_branch}"
		${git_bin} pull --no-edit https://gitlab.denx.de/Xenomai/ipipe-arm.git ${xenomai_branch}
		${git_bin} diff ${kernel_base}...HEAD > ../patches/ipipe/ipipe.diff

		sed -i -s 's:arch/arm/plat-omap/include/plat/dmtimer.h:include/clocksource/timer-ti-dm.h:g' ../patches/ipipe/ipipe.diff
		sed -i -s 's:arch/arm/plat-omap/dmtimer.c:drivers/clocksource/timer-ti-dm.c:g' ../patches/ipipe/ipipe.diff
		sed -i -s 's:__ASM_ARCH_DMTIMER_H:CONFIG_ARCH_OMAP1 || CONFIG_ARCH_OMAP2PLUS:g' ../patches/ipipe/ipipe.diff

		${git_bin} checkout v${KERNEL_TAG}${BUILD} -f
		test_for_branch=$(${git_bin} branch --list "${xenomai_branch}")
		if [ "x${test_for_branch}" != "x" ] ; then
			${git_bin} branch "${xenomai_branch}" -D
		fi

		cp -v ../patches/ipipe/drivers_pci_dwc_pcie-designware-host.c drivers/pci/dwc/pcie-designware-host.c

		cp -v ../patches/ipipe/drivers_pinctrl_bcm_pinctrl-bcm2835.c drivers/pinctrl/bcm/pinctrl-bcm2835.c

		#exit 2

		${git_bin} add --all
		${git_bin} commit --allow-empty -a -m 'xenomai pre-patchset'

		sed -i -s 's:#endif :\n#endif :g' include/clocksource/timer-ti-dm.h
		sed -i -s 's:#ifdef CONFIG_MMU:\n#ifdef CONFIG_MMU:g' arch/arm/include/asm/uaccess.h

		patch -p1 < ../patches/ipipe/ipipe.diff

		#drivers/clocksource/timer-ti-dm.c
		#include/clocksource/timer-ti-dm.h

		${git_bin} add --all
		${git_bin} commit -a -m 'xenomai ipipe patchset'
		${git_bin} format-patch -2 -o ../patches/ipipe/

		${git_bin} reset --hard HEAD~2

		start_cleanup

		${git} "${DIR}/patches/ipipe/0001-xenomai-pre-patchset.patch"
		${git} "${DIR}/patches/ipipe/0002-xenomai-ipipe-patchset.patch"

		wdir="ipipe"
		number=2
		cleanup
	fi

	${git} "${DIR}/patches/ipipe/0001-xenomai-pre-patchset.patch"
	${git} "${DIR}/patches/ipipe/0002-xenomai-ipipe-patchset.patch"

	echo "dir: xenomai - prepare_kernel"
	# Add the rest of xenomai to the kernel
	OUTPATCH=$(mktemp "${DIR}/ignore/xenomai-patch.XXXXXXXXXX") || { echo "Failed to create temp file"; exit 1; }

	# generate the xenomai patch
	# doing it this way fixes the dangling symlinks problem under /usr/src/linux-headers-*
	${DIR}/ignore/xenomai/scripts/prepare-kernel.sh --linux=./ --arch=arm --outpatch="${OUTPATCH}"

	# and apply it
	${git_bin} apply "${OUTPATCH}"

	${git_bin} add .
	${git_bin} commit -a -m 'xenomai patchset'

	if [ "x${regenerate}" = "xenable" ] ; then
		exit 2
	fi
}

ipipe

pre_backports () {
	echo "dir: backports/${subsystem}"

	cd ~/linux-src/
	${git_bin} pull --no-edit https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git master
	${git_bin} pull --no-edit https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git master --tags
	${git_bin} pull --no-edit https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git master --tags
	if [ ! "x${backport_tag}" = "x" ] ; then
		${git_bin} checkout ${backport_tag} -b tmp
	fi
	cd -
}

post_backports () {
	if [ ! "x${backport_tag}" = "x" ] ; then
		cd ~/linux-src/
		${git_bin} checkout master -f ; ${git_bin} branch -D tmp
		cd -
	fi

	${git_bin} add .
	${git_bin} commit -a -m "backports: ${subsystem}: from: linux.git" -s
	if [ ! -d ../patches/backports/${subsystem}/ ] ; then
		mkdir -p ../patches/backports/${subsystem}/
	fi
	${git_bin} format-patch -1 -o ../patches/backports/${subsystem}/
}

patch_backports (){
	echo "dir: backports/${subsystem}"
	${git} "${DIR}/patches/backports/${subsystem}/0001-backports-${subsystem}-from-linux.git.patch"
}

backports () {
	backport_tag="v4.16.18"

	subsystem="typec"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		pre_backports

		cp -rv ~/linux-src/drivers/usb/typec/* ./drivers/usb/typec/
		cp -v ~/linux-src/include/linux/usb/pd.h ./include/linux/usb/pd.h
		cp -v ~/linux-src/include/linux/usb/pd_bdo.h ./include/linux/usb/pd_bdo.h
		cp -v ~/linux-src/include/linux/usb/pd_vdo.h ./include/linux/usb/pd_vdo.h
		cp -v ~/linux-src/include/linux/usb/tcpm.h ./include/linux/usb/tcpm.h
		cp -v ~/linux-src/include/linux/usb/typec.h ./include/linux/usb/typec.h

		#Cleanup old Staging version of typec...
		rm -rf ./drivers/staging/typec/

		post_backports
	else
		patch_backports
	fi

	${git} "${DIR}/patches/backports/typec/0002-unstage-typec.patch"

	backport_tag="v5.0.6"

	subsystem="vl53l0x"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		pre_backports

		cp -v ~/linux-src/drivers/iio/proximity/vl53l0x-i2c.c ./drivers/iio/proximity/vl53l0x-i2c.c

		post_backports
		exit 2
	else
		patch_backports
	fi

	${git} "${DIR}/patches/backports/vl53l0x/0002-wire-up-VL53L0X_I2C.patch"

	backport_tag="v5.2-rc5"
	subsystem="brcm80211"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		pre_backports

		cp -rv ~/linux-src/drivers/net/wireless/broadcom/brcm80211/* ./drivers/net/wireless/broadcom/brcm80211/
		cp -v ~/linux-src/include/linux/mmc/sdio_ids.h ./include/linux/mmc/sdio_ids.h
		#cp -v ~/linux-src/include/linux/firmware.h ./include/linux/firmware.h

		post_backports
		exit 2
	else
		patch_backports
	fi

	${git} "${DIR}/patches/backports/brcm80211/0002-revert-brcmfmac-add-debugfs-entry-for-reading-firmwa.patch"
	${git} "${DIR}/patches/backports/brcm80211/0004-revert-brcmfmac-Use-__skb_peek.patch"
	${git} "${DIR}/patches/backports/brcm80211/0005-revert-brcmfmac-Use-firmware_request_nowarn-for-the-.patch"
	${git} "${DIR}/patches/backports/brcm80211/0006-revert-brcmfmac-Use-standard-SKB-list-accessors-in-b.patch"
	${git} "${DIR}/patches/backports/brcm80211/0007-revert-brcmfmac-Use-struct_size-in-kzalloc.patch"
}

reverts () {
	echo "dir: reverts"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		start_cleanup
	fi

	#https://github.com/torvalds/linux/commit/00f0ea70d2b82b7d7afeb1bdedc9169eb8ea6675
	#
	#Causes bone_capemgr to get stuck on slot 1 and just eventually exit "without" checking slot2/3/4...
	#
	#[    5.406775] bone_capemgr bone_capemgr: Baseboard: 'A335BNLT,00C0,2516BBBK2626'
	#[    5.414178] bone_capemgr bone_capemgr: compatible-baseboard=ti,beaglebone-black - #slots=4
	#[    5.422573] bone_capemgr bone_capemgr: Failed to add slot #1

	${git} "${DIR}/patches/reverts/0001-Revert-eeprom-at24-check-if-the-chip-is-functional-i.patch"
	${git} "${DIR}/patches/reverts/0002-Revert-tis-overlay-setup.patch"

	if [ "x${regenerate}" = "xenable" ] ; then
		wdir="reverts"
		number=2
		cleanup
	fi
}

drivers () {
	dir 'drivers/ar1021_i2c'
#	dir 'drivers/bcmdhd'
	dir 'drivers/btrfs'
	dir 'drivers/mcp23s08'
	dir 'drivers/pwm'
	dir 'drivers/snd_pwmsp'
	dir 'drivers/sound'
	dir 'drivers/spi'
	dir 'drivers/ssd1306'
	dir 'drivers/tps65217'
	dir 'drivers/opp'
	dir 'drivers/wiznet'

	#https://github.com/pantoniou/linux-beagle-track-mainline/tree/bbb-overlays
	echo "dir: drivers/ti/bbb_overlays"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		start_cleanup
	fi

	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0001-gitignore-Ignore-DTB-files.patch"

	if [ "x${regenerate}" = "xenable" ] ; then
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0002-add-PM-firmware.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0003-ARM-CUSTOM-Build-a-uImage-with-dtb-already-appended.patch"
	fi

	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0004-omap-Fix-crash-when-omap-device-is-disabled.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0005-serial-omap-Fix-port-line-number-without-aliases.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0006-tty-omap-serial-Fix-up-platform-data-alloc.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0007-of-overlay-kobjectify-overlay-objects.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0008-of-overlay-global-sysfs-enable-attribute.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0009-Documentation-ABI-overlays-global-attributes.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0010-Documentation-document-of_overlay_disable-parameter.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0011-of-overlay-add-per-overlay-sysfs-attributes.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0012-Documentation-ABI-overlays-per-overlay-docs.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0013-of-dynamic-Add-__of_node_dupv.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0014-of-changesets-Introduce-changeset-helper-methods.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0015-of-changeset-Add-of_changeset_node_move-method.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0016-of-unittest-changeset-helpers.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0017-OF-DT-Overlay-configfs-interface-v7.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0018-ARM-DT-Enable-symbols-when-CONFIG_OF_OVERLAY-is-used.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0019-misc-Beaglebone-capemanager.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0020-doc-misc-Beaglebone-capemanager-documentation.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0021-doc-dt-beaglebone-cape-manager-bindings.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0022-doc-ABI-bone_capemgr-sysfs-API.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0023-MAINTAINERS-Beaglebone-capemanager-maintainer.patch"

	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0025-of-overlay-Implement-target-index-support.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0026-of-unittest-Add-indirect-overlay-target-test.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0027-doc-dt-Document-the-indirect-overlay-method.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0028-of-overlay-Introduce-target-root-capability.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0029-of-unittest-Unit-tests-for-target-root-overlays.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0030-doc-dt-Document-the-target-root-overlay-method.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0031-RFC-Device-overlay-manager-PCI-USB-DT.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0032-of-rename-_node_sysfs-to-_node_post.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0033-of-Support-hashtable-lookups-for-phandles.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0034-of-unittest-hashed-phandles-unitest.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0035-of-overlay-Pick-up-label-symbols-from-overlays.patch"


	if [ "x${regenerate}" = "xenable" ] ; then
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0036-of-Portable-Device-Tree-connector.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0037-boneblack-defconfig.patch"
	fi

	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0038-bone_capemgr-uboot_capemgr_enabled-flag.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0039-bone_capemgr-kill-with-uboot-flag.patch"
	${git} "${DIR}/patches/drivers/ti/bbb_overlays/0040-fix-include-linux-of.h-add-linux-slab.h-include.patch"

	if [ "x${regenerate}" = "xenable" ] ; then
		wdir="drivers/ti/bbb_overlays"
		number=40
		cleanup
	fi

	dir 'drivers/ti/cpsw'
	dir 'drivers/ti/etnaviv'
	dir 'drivers/ti/eqep'
	dir 'drivers/ti/rpmsg'
	dir 'drivers/ti/pru_rproc'
	dir 'drivers/ti/serial'
	dir 'drivers/ti/tsc'
	dir 'drivers/ti/uio'
	dir 'drivers/ti/gpio'

	cdir="patches/cypress/v4.14.77-2019_0503/cypress-patch"

	echo "dir: cypress/v4.14.77-2019_0503/cypress-patch"

#	${git} "${DIR}/${cdir}/0001-brcmfmac-add-CLM-download-support.patch" # v4.15.x
#	${git} "${DIR}/${cdir}/0002-brcmfmac-Set-F2-blksz-and-Watermark-to-256-for-4373.patch" # not us...
	${git} "${DIR}/${cdir}/0003-brcmfmac-Add-sg-parameters-dts-parsing.patch"
#	${git} "${DIR}/${cdir}/0004-brcmfmac-return-EPERM-when-getting-error-in-vendor-c.patch" # v4.16.x
#	${git} "${DIR}/${cdir}/0005-brcmfmac-Add-support-for-CYW43012-SDIO-chipset.patch" # not us...
#	${git} "${DIR}/${cdir}/0006-brcmfmac-set-apsta-to-0-when-AP-starts-on-primary-in.patch"
#	${git} "${DIR}/${cdir}/0007-brcmfmac-Saverestore-support-changes-for-43012.patch" # v4.16.x
#	${git} "${DIR}/${cdir}/0008-brcmfmac-Support-43455-save-restore-SR-feature-if-FW.patch" # v4.16.x
#	${git} "${DIR}/${cdir}/0009-brcmfmac-fix-CLM-load-error-for-legacy-chips-when-us.patch" # v4.15.x
#	${git} "${DIR}/${cdir}/0010-brcmfmac-enlarge-buffer-size-of-caps-to-512-bytes.patch" # v4.16.x
#	${git} "${DIR}/${cdir}/0011-brcmfmac-calling-skb_orphan-before-sending-skb-to-SD.patch"
#	${git} "${DIR}/${cdir}/0012-brcmfmac-43012-Update-F2-Watermark-to-0x60-to-fix-DM.patch" # not us...
#	${git} "${DIR}/${cdir}/0013-brcmfmac-DS1-Exit-should-re-download-the-firmware.patch"
#	${git} "${DIR}/${cdir}/0014-brcmfmac-add-FT-based-AKMs-in-brcmf_set_key_mgmt-for.patch"
#	${git} "${DIR}/${cdir}/0015-brcmfmac-support-AP-isolation.patch"
#	${git} "${DIR}/${cdir}/0016-brcmfmac-do-not-print-ulp_sdioctrl-get-error.patch"
#	${git} "${DIR}/${cdir}/0017-brcmfmac-fix-system-warning-message-during-wowl-susp.patch"
#	${git} "${DIR}/${cdir}/0018-brcmfmac-add-a-module-parameter-to-set-scheduling-pr.patch"
#	${git} "${DIR}/${cdir}/0019-brcmfmac-make-firmware-eap_restrict-a-module-paramet.patch"
#	${git} "${DIR}/${cdir}/0020-brcmfmac-Support-wake-on-ping-packet.patch"
#	${git} "${DIR}/${cdir}/0021-brcmfmac-Remove-WOWL-configuration-in-disconnect-sta.patch"
#	${git} "${DIR}/${cdir}/0022-brcmfmac-add-CYW89342-PCIE-device.patch"
#	${git} "${DIR}/${cdir}/0023-brcmfmac-handle-compressed-tx-status-signal.patch"
#	${git} "${DIR}/${cdir}/0024-revert-brcmfmac-add-a-module-parameter-to-set-schedu.patch"
#	${git} "${DIR}/${cdir}/0025-brcmfmac-make-setting-SDIO-workqueue-WQ_HIGHPRI-a-mo.patch"
#	${git} "${DIR}/${cdir}/0026-brcmfmac-add-credit-map-updating-support.patch"
#	${git} "${DIR}/${cdir}/0027-brcmfmac-add-4-way-handshake-offload-detection-for-F.patch"
#	${git} "${DIR}/${cdir}/0028-brcmfmac-remove-arp_hostip_clear-from-brcmf_netdev_s.patch"
#	${git} "${DIR}/${cdir}/0029-brcmfmac-fix-unused-variable-building-warning-messag.patch"
#	${git} "${DIR}/${cdir}/0030-brcmfmac-disable-command-decode-in-sdio_aos-for-4339.patch"
#	${git} "${DIR}/${cdir}/0031-Revert-brcmfmac-fix-CLM-load-error-for-legacy-chips-.patch" # v4.15.x
#	${git} "${DIR}/${cdir}/0032-brcmfmac-fix-CLM-load-error-for-legacy-chips-when-us.patch" # v4.15.x
#	${git} "${DIR}/${cdir}/0033-brcmfmac-set-WIPHY_FLAG_HAVE_AP_SME-flag.patch"
#	${git} "${DIR}/${cdir}/0034-brcmfmac-P2P-CERT-6.1.9-Support-GOUT-handling-P2P-Pr.patch"
#	${git} "${DIR}/${cdir}/0035-brcmfmac-only-generate-random-p2p-address-when-neede.patch"
#	${git} "${DIR}/${cdir}/0036-brcmfmac-disable-command-decode-in-sdio_aos-for-4354.patch"
#	${git} "${DIR}/${cdir}/0037-brcmfmac-increase-max-hanger-slots-from-1K-to-3K-in-.patch"
#	${git} "${DIR}/${cdir}/0038-brcmfmac-reduce-timeout-for-action-frame-scan.patch"
#	${git} "${DIR}/${cdir}/0039-brcmfmac-fix-full-timeout-waiting-for-action-frame-o.patch"
#	${git} "${DIR}/${cdir}/0040-brcmfmac-4373-save-restore-support.patch"
#	${git} "${DIR}/${cdir}/0041-brcmfmac-map-802.1d-priority-to-precedence-level-bas.patch"
#	${git} "${DIR}/${cdir}/0042-brcmfmac-allow-GCI-core-enumuration.patch"
#	${git} "${DIR}/${cdir}/0043-brcmfmac-make-firmware-frameburst-mode-a-module-para.patch"
#	${git} "${DIR}/${cdir}/0044-brcmfmac-set-state-of-hanger-slot-to-FREE-when-flush.patch"
#	${git} "${DIR}/${cdir}/0045-brcmfmac-add-creating-station-interface-support.patch"
#	${git} "${DIR}/${cdir}/0046-brcmfmac-add-RSDB-condition-when-setting-interface-c.patch"
#	${git} "${DIR}/${cdir}/0047-brcmfmac-not-set-mbss-in-vif-if-firmware-does-not-su.patch"
#	${git} "${DIR}/${cdir}/0048-brcmfmac-support-the-second-p2p-connection.patch"
#	${git} "${DIR}/${cdir}/0049-brcmfmac-Add-support-for-BCM4359-SDIO-chipset.patch"
#	${git} "${DIR}/${cdir}/0050-cfg80211-nl80211-add-a-port-authorized-event.patch"
#	${git} "${DIR}/${cdir}/0051-nl80211-add-NL80211_ATTR_IFINDEX-to-port-authorized-.patch"
#	${git} "${DIR}/${cdir}/0052-brcmfmac-send-port-authorized-event-for-802.1X-4-way.patch"
#	${git} "${DIR}/${cdir}/0053-brcmfmac-send-port-authorized-event-for-FT-802.1X.patch"
#	${git} "${DIR}/${cdir}/0054-brcmfmac-Support-DS1-TX-Exit-in-FMAC.patch"
#	${git} "${DIR}/${cdir}/0055-brcmfmac-disable-command-decode-in-sdio_aos-for-4373.patch"
#	${git} "${DIR}/${cdir}/0056-brcmfmac-add-vendor-ie-for-association-responses.patch"
#	${git} "${DIR}/${cdir}/0057-brcmfmac-fix-43012-insmod-after-rmmod-in-DS1-failure.patch"
#	${git} "${DIR}/${cdir}/0058-brcmfmac-Set-SDIO-F1-MesBusyCtrl-for-CYW4373.patch"
#	${git} "${DIR}/${cdir}/0059-brcmfmac-add-4354-raw-pcie-device-id.patch"
#	${git} "${DIR}/${cdir}/0060-nl80211-Allow-SAE-Authentication-for-NL80211_CMD_CON.patch"
#	${git} "${DIR}/${cdir}/0061-non-upstream-update-enum-nl80211_attrs-and-nl80211_e.patch"
#	${git} "${DIR}/${cdir}/0062-nl80211-add-WPA3-definition-for-SAE-authentication.patch"
#	${git} "${DIR}/${cdir}/0063-cfg80211-add-support-for-SAE-authentication-offload.patch"
#	${git} "${DIR}/${cdir}/0064-brcmfmac-add-support-for-SAE-authentication-offload.patch"
#	${git} "${DIR}/${cdir}/0065-brcmfmac-fix-4339-CRC-error-under-SDIO-3.0-SDR104-mo.patch"
#	${git} "${DIR}/${cdir}/0066-brcmfmac-fix-the-incorrect-return-value-in-brcmf_inf.patch"
#	${git} "${DIR}/${cdir}/0067-brcmfmac-Fix-double-freeing-in-the-fmac-usb-data-pat.patch"
#	${git} "${DIR}/${cdir}/0068-brcmfmac-Fix-driver-crash-on-USB-control-transfer-ti.patch"
#	${git} "${DIR}/${cdir}/0069-brcmfmac-avoid-network-disconnection-during-suspend-.patch"
#	${git} "${DIR}/${cdir}/0070-brcmfmac-Allow-credit-borrowing-for-all-access-categ.patch"
#	${git} "${DIR}/${cdir}/0071-non-upstream-Changes-to-improve-USB-Tx-throughput.patch"
#	${git} "${DIR}/${cdir}/0072-non-upstream-reset-two-D11-cores-if-chip-has-two-D11.patch"
#	${git} "${DIR}/${cdir}/0073-brcmfmac-reset-PMU-backplane-all-cores-in-CYW4373-du.patch"
#	${git} "${DIR}/${cdir}/0074-brcmfmac-introduce-module-parameter-to-configure-def.patch"
#	${git} "${DIR}/${cdir}/0075-brcmfmac-configure-wowl-parameters-in-suspend-functi.patch"
#	${git} "${DIR}/${cdir}/0076-brcmfmac-discard-user-space-RSNE-for-SAE-authenticat.patch"
#	${git} "${DIR}/${cdir}/0077-brcmfmac-keep-SDIO-watchdog-running-when-console_int.patch"
#	${git} "${DIR}/${cdir}/0078-brcmfmac-To-fix-kernel-crash-on-out-of-boundary-acce.patch"
#	${git} "${DIR}/${cdir}/0079-brcmfmac-reduce-maximum-station-interface-from-2-to-.patch"
#	${git} "${DIR}/${cdir}/0080-Revert-brcmfmac-add-creating-station-interface-suppo.patch"
#	${git} "${DIR}/${cdir}/0081-brcmfmac-validate-ifp-pointer-in-brcmf_txfinalize.patch"
#	${git} "${DIR}/${cdir}/0082-brcmfmac-clean-up-iface-mac-descriptor-before-de-ini.patch"
#	${git} "${DIR}/${cdir}/0083-brcmfmac-To-support-printing-USB-console-messages.patch"
#	${git} "${DIR}/${cdir}/0084-brcmfmac-To-fix-Bss-Info-flag-definition-Bug.patch"
#	${git} "${DIR}/${cdir}/0085-brcmfmac-disable-command-decode-in-sdio_aos-for-4356.patch"
#	${git} "${DIR}/${cdir}/0086-brcmfmac-increase-default-max-WOWL-patterns-to-16.patch"
#	${git} "${DIR}/${cdir}/0087-brcmfmac-Enable-Process-and-forward-PHY_TEMP-event.patch"
#	${git} "${DIR}/${cdir}/0088-brcmfmac-add-USB-autosuspend-feature-support.patch"
#	${git} "${DIR}/${cdir}/0089-non-upstream-workaround-for-4373-USB-WMM-5.2.27-test.patch"
#	${git} "${DIR}/${cdir}/0090-brcmfmac-Fix-access-point-mode.patch"
#	${git} "${DIR}/${cdir}/0091-brcmfmac-make-compatible-with-Fully-Preemptile-Kerne.patch"
#	${git} "${DIR}/${cdir}/0092-brcmfmac-remove-the-duplicate-line-of-writing-BRCMF_.patch"
#	${git} "${DIR}/${cdir}/0093-brcmfmac-43012-reloading-FAMC-driver-failure-on-BU-m.patch"
#	${git} "${DIR}/${cdir}/0094-brcmfmac-handle-FWHALT-mailbox-indication.patch" # v4.15.x
#	${git} "${DIR}/${cdir}/0095-brcmfmac-validate-user-provided-data-for-memdump-bef.patch"
#	${git} "${DIR}/${cdir}/0096-brcmfmac-Use-FW-priority-definition-to-initialize-WM.patch"
#	${git} "${DIR}/${cdir}/0097-brcmfmac-Fix-P2P-Group-Formation-failure-via-Go-neg-.patch"
#	${git} "${DIR}/${cdir}/0098-nl80211-add-authorized-flag-back-to-ROAM-event.patch"
#	${git} "${DIR}/${cdir}/0099-brcmfmac-set-authorized-flag-in-ROAM-event-for-offlo.patch"
#	${git} "${DIR}/${cdir}/0100-brcmfmac-allocate-msgbuf-pktid-from-1-to-size-of-pkt.patch"
#	${git} "${DIR}/${cdir}/0101-brcmfmac-Add-P2P-Action-Frame-retry-delay-to-fix-GAS.patch"
#	${git} "${DIR}/${cdir}/0102-brcmfmac-Use-default-FW-priority-when-EDCA-params-sa.patch"
#	${git} "${DIR}/${cdir}/0103-brcmfmac-set-authorized-flag-in-ROAM-event-for-PMK-c.patch"
#	${git} "${DIR}/${cdir}/0104-brcmfmac-fix-continuous-802.1x-tx-pending-timeout-er.patch"
#	${git} "${DIR}/${cdir}/0105-brcmfmac-add-sleep-in-bus-suspend-and-cfg80211-resum.patch"
#	${git} "${DIR}/${cdir}/0106-brcmfmac-fix-43455-CRC-error-under-SDIO-3.0-SDR104-m.patch"
#	${git} "${DIR}/${cdir}/0107-brcmfmac-set-F2-blocksize-and-watermark-for-4359.patch"
#	${git} "${DIR}/${cdir}/0108-brcmfmac-add-subtype-check-for-event-handling-in-dat.patch"
#	${git} "${DIR}/${cdir}/0109-brcmfmac-assure-SSID-length-from-firmware-is-limited.patch"
#	${git} "${DIR}/${cdir}/0110-nl80211-add-authorized-flag-to-CONNECT-event.patch"
#	${git} "${DIR}/${cdir}/0111-brcmfmac-set-authorized-flag-in-CONNECT-event-for-PM.patch"
}

soc () {
	dir 'soc/ti/abbbi'

	dir 'soc/gssi'
	dir 'soc/ti/beagleboneai'
}

###
backports
reverts
drivers
soc

packaging () {
	echo "dir: packaging"
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		cp -v "${DIR}/3rdparty/packaging/Makefile" "${DIR}/KERNEL/scripts/package"
		cp -v "${DIR}/3rdparty/packaging/builddeb" "${DIR}/KERNEL/scripts/package"
		#Needed for v4.11.x and less
		#patch -p1 < "${DIR}/patches/packaging/0002-Revert-deb-pkg-Remove-the-KBUILD_IMAGE-workaround.patch"
		${git_bin} commit -a -m 'packaging: sync builddeb changes' -s
		${git_bin} format-patch -1 -o "${DIR}/patches/packaging"
		exit 2
	else
		${git} "${DIR}/patches/packaging/0001-packaging-sync-builddeb-changes.patch"
	fi
}

readme () {
	#regenerate="enable"
	if [ "x${regenerate}" = "xenable" ] ; then
		cp -v "${DIR}/3rdparty/readme/README.md" "${DIR}/KERNEL/README.md"
		cp -v "${DIR}/3rdparty/readme/jenkins_build.sh" "${DIR}/KERNEL/jenkins_build.sh"
		cp -v "${DIR}/3rdparty/readme/Jenkinsfile" "${DIR}/KERNEL/Jenkinsfile"
		git add -f README.md
		git add -f jenkins_build.sh
		git add -f Jenkinsfile
		git commit -a -m 'enable: Jenkins: http://gfnd.rcn-ee.org:8080' -s
		git format-patch -1 -o "${DIR}/patches/readme"
		exit 2
	else
		dir 'readme'
	fi
}

packaging
readme
echo "patch.sh ran successfully"

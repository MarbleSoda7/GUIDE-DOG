SUMMARY = "Dual OV5640 capture and camera2 PL UDP service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://camremap \
           file://data \
           file://camremap-init \
          "
S = "${WORKDIR}"

inherit update-rc.d python3-dir

INITSCRIPT_NAME = "camremap"
INITSCRIPT_PARAMS = "start 99 2 3 4 5 . stop 20 0 1 6 ."

RDEPENDS:${PN} = "python3-modules python3-numpy"

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}/camremap
    install -m 0644 ${WORKDIR}/camremap/*.py ${D}${PYTHON_SITEPACKAGES_DIR}/camremap/
    install -d ${D}${datadir}/camremap
    install -m 0644 ${WORKDIR}/data/* ${D}${datadir}/camremap/
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/camremap-init ${D}${sysconfdir}/init.d/camremap
}

FILES:${PN} += "${PYTHON_SITEPACKAGES_DIR}/camremap ${datadir}/camremap"

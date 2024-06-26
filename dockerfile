#########################
### Setup environment ###
#########################
FROM ubuntu:22.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake \
    vim git sudo wget tar \
    bison flex texinfo pkg-config \
    unzip xz-utils lzop bsdmainutils \
    device-tree-compiler u-boot-tools libexpat1-dev \
    python3 python3-dev libpython3-dev python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

#################################
### Install rtems build tools ###
#################################
# This step takes a long time! ~1hr
RUN cd /usr/src && \
    git clone https://gitlab.rtems.org/rtems/tools/rtems-source-builder.git rsb && \
    cd /usr/src/rsb/rtems && \
    git checkout 4c6dfb7aef9811258457971aa9213d5aebb9ce8d && \
    ../source-builder/sb-set-builder --prefix=/opt/rtems/6 6/rtems-arm
ENV PATH="/opt/rtems/6/bin:${PATH}"

#################################################
### Copy edited rtems source and linker files ###
#################################################
# system_samv71.c includes an updated clock configuration to support the SMC.
# ata.c, ide_controller.c, ide_ctrl_cfg.h have references to deprecated, build-breaking variables commented out.
# linkcmds and linkcmds.memory were updated to use the external MRAM for REGION_BSS, REGION_WORK, and REGION_STACK.
COPY system_samv71.c /system_samv71.c
COPY ata.c /ata.c
COPY ide_controller.c /ide_controller.c
COPY ide_ctrl_cfg.h /ide_ctrl_cfg.h
COPY linkcmds /linkcmds
COPY linkcmds.memory /linkcmds.memory

######################################
### Install atsamv BSP from source ###
######################################
# The edited source files must be placed in the repository before the waf build/install.
# The edited linker files are placed in the bsp after it is installed.
COPY config.ini /config.ini
RUN cd /usr/src && \
    git clone https://gitlab.rtems.org/rtems/rtos/rtems.git rtems && \
    cd /usr/src/rtems && \
    git checkout e5b6fa026ac1c07d252233624054785b2b29f54e && \
    mv -f /system_samv71.c ./bsps/arm/atsam/contrib/libraries/libboard/resources_v71/system_samv71.c && \
    mv -f /ata.c ./bsps/shared/dev/ide/ata.c && \
    mv -f /ide_controller.c ./bsps/shared/dev/ide/ide_controller.c && \
    mv -f /ide_ctrl_cfg.h ./bsps/include/libchip/ide_ctrl_cfg.h && \
    mv /config.ini ./config.ini && \
    ./waf configure --prefix=/opt/rtems/6 && \
    ./waf && \
    ./waf install && \
    mv -f /linkcmds /opt/rtems/6/arm-rtems6/atsamv/lib/linkcmds && \
    mv -f /linkcmds.memory /opt/rtems/6/arm-rtems6/atsamv/lib/linkcmds.memory

######################################
### Clone CFS repository and build ###
######################################
# This fork of the nasa cFS repository includes an arm-atsamv-rtems6 toolchain and
# has networking functionality removed from the osal and psp. The networking code
# breaks the build unless rtems-libbsd is installed. rtems-libsd was unable to be installed
# because of memory limitations.
RUN cd /usr/src && \
    git clone https://github.com/smithshady/cFS.git cFS && \
    cd /usr/src/cFS && \
    git submodule update --init --recursive && \
    make SIMULATION=arm-atsamv-rtems6 prep && \
    make && \
    make install
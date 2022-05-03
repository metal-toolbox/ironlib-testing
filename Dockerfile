FROM centos:centos8 AS stage0
ARG TOOLING_ENDPOINT=https://equinix-metal-firmware.s3.amazonaws.com/fup/image-tooling
ARG ASRDEV_KERNEL_MODULE=asrdev-5.4.0-73-generic.ko

# point centos mirrors to vault - since Centos 8 is deprecated
# - comment out mirrorlist URL
# - point baseurl to vault
# - un-comment baseurl
RUN sed -e '/mirrorlist=/ s/^#*/#/' \
        -e '/baseurl=/ s/mirror.centos.org/install.packet.net/' \
        -e '/baseurl=/ s/^#*//' -i \
           /etc/yum.repos.d/CentOS-Linux-AppStream.repo \
           /etc/yum.repos.d/CentOS-Linux-BaseOS.repo \
           /etc/yum.repos.d/CentOS-Linux-Extras.repo

## install build utils
RUN dnf install -y --setopt=tsflags=nodocs \
                              gcc          \
                              flex         \
                              make         \
                              bison        \
                              patch        \
                              ctags        \
                              gcc-c++      \
                              gettext      \
                              libtool      \
                              elfutils     \
                              autoconf     \
                              automake     \
                              binutils     \
                              pkgconfig    \
                              patchutils   \
                              kernel-devel \
                              unzip


## fetch vendor tools
RUN set -x; \
    curl -sO $TOOLING_ENDPOINT/mlxup && \
    curl -sO $TOOLING_ENDPOINT/msecli_Linux.run && \
    curl -sO $TOOLING_ENDPOINT/IPMICFG_1.32.0_build.200910.zip && \
    curl -sO $TOOLING_ENDPOINT/sum_2.5.0_Linux_x86_64_20200722.tar.gz && \
    curl -sO $TOOLING_ENDPOINT/SW_Broadcom_Unified_StorCLI_v007.1316.0000.0000_20200428.ZIP && \
    curl -sO $TOOLING_ENDPOINT/asrr/BIOSControl_v1.0.3.zip && \
    curl -sO $TOOLING_ENDPOINT/asrr/asrr_bios_kernel_module/$ASRDEV_KERNEL_MODULE && \
    # install mlxup
    install -m 755 -D mlxup /usr/sbin/ && \
    # install SMC sum 2.5.0
    tar -xvzf sum_2.5.0_Linux_x86_64_20200722.tar.gz && \
    install -m 755 -D sum_2.5.0_Linux_x86_64/sum /usr/sbin/ && \
    # install SMC ipmicfg
    unzip IPMICFG_1.32.0_build.200910.zip && \
    install -m 755 -D IPMICFG_1.32.0_build.200910/Linux/64bit/IPMICFG-Linux.x86_64 /usr/sbin/smc-ipmicfg && \
    # install storecli
    unzip SW_Broadcom_Unified_StorCLI_v007.1316.0000.0000_20200428.ZIP && \
    unzip BIOSControl_v1.0.3.zip && \
    install -m 755 -D BIOSControl /usr/sbin/asrr-bioscontrol && \
    # fetch Dell PGP keys
    mkdir dell_pgp_keys && cd dell_pgp_keys && \
    curl -sO $TOOLING_ENDPOINT/dell/pgp_keys/0x756ba70b1019ced6.asc && \
    curl -sO $TOOLING_ENDPOINT/dell/pgp_keys/0xca77951d23b66a9d.asc && \
    curl -sO $TOOLING_ENDPOINT/dell/pgp_keys/0x1285491434D8786F.asc && \
    curl -sO $TOOLING_ENDPOINT/dell/pgp_keys/0x3CA66B4946770C59.asc

# build ironlib wrapper binaries
FROM golang:1.16-alpine AS stage1

WORKDIR /workspace

# copy the go modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# copy the go sources
COPY . .

# build helper util
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -o getbiosconfig examples/biosconfig/biosconfig.go && \
    install -m 755 -D getbiosconfig /usr/sbin/

# main
FROM centos:centos8
LABEL author="Joel Rebello<jrebello@packet.com>"
# copy vendor tooling artifacts
COPY --from=stage0 /usr/sbin/mlxup /usr/sbin/mlxup
COPY --from=stage0 /usr/sbin/sum /usr/sbin/sum
COPY --from=stage0 /usr/sbin/smc-ipmicfg /usr/sbin/smc-ipmicfg
COPY --from=stage0 Unified_storcli_all_os/Linux/pubKey.asc /tmp/storecli_pubkey.asc
COPY --from=stage0 Unified_storcli_all_os/Linux/storcli-007.1316.0000.0000-1.noarch.rpm /tmp/
COPY --from=stage0 msecli_Linux.run /tmp/

# copy updated centos 8 repo files pointing to vault
COPY --from=stage0 /etc/yum.repos.d/CentOS-Linux-AppStream.repo /etc/yum.repos.d/CentOS-Linux-AppStream.repo
COPY --from=stage0 /etc/yum.repos.d/CentOS-Linux-BaseOS.repo /etc/yum.repos.d/CentOS-Linux-BaseOS.repo
COPY --from=stage0 /etc/yum.repos.d/CentOS-Linux-Extras.repo /etc/yum.repos.d/CentOS-Linux-Extras.repo

# copy ironlib wrapper binaries
COPY --from=stage1 /usr/sbin/getbiosconfig /usr/sbin/getbiosconfig

# import and install tools
RUN rpm --import /tmp/storecli_pubkey.asc && \
    dnf install -y /tmp/storcli-007.1316.0000.0000-1.noarch.rpm && \
    chmod 755 /tmp/msecli_Linux.run && /tmp/msecli_Linux.run --mode unattended && rm -rf /tmp/*

############# Dell ####################
COPY dell-system-update.repo /etc/yum.repos.d/
## Prerequisite directories for Dell, ASRR
## /lib/firmware required for Dell updates to be installed successfullly
RUN mkdir -p /lib/firmware /opt/asrr /usr/libexec/dell_dup

# asrr
# asrr bios settings util requires a kernel module, ugh - the module is loaded
# when the asrr utility is invoked in ironlib
COPY --from=stage0 /usr/sbin/asrr-bioscontrol /usr/sbin/asrr-bioscontrol
COPY --from=stage0 asrdev*.*.ko /opt/asrr
COPY --from=stage0 dell_pgp_keys/* /usr/libexec/dell_dup/

# install misc support packages
RUN dnf install -y --setopt=tsflags=nodocs https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    dnf install -y --setopt=tsflags=nodocs \
                   vim           \
                   tar           \
                   lshw          \
                   unzip         \
                   nano          \
                   gzip          \
                   less          \
                   which         \
                   strace        \
                   pciutils      \
                   passwd        \
                   nvme-cli      \
                   dmidecode     \
                   libssh2-devel \
                   smartmontools \
                   'dnf-command(config-manager)' && \
    dnf config-manager --disable production-dell-system-update_dependent && \
    dnf config-manager --disable production-dell-system-update_independent && \
    dnf clean all

ENTRYPOINT [ "/bin/bash", "-l", "-c" ]
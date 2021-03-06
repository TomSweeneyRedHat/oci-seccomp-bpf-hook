#!/bin/bash

# Script used by CI to configure both container and VM environments.

set -e

source $(dirname $0)/lib.sh

cd $GOSRC

# Only Output on Error wrapper
install_ooe

CRITICAL_PKGS=()
INSTALL_PACKAGES=()

case "$OS_RELEASE_ID" in
    fedora)
        INSTALL_COMMAND='dnf install -y'
        LIST_COMMAND='rpm -q --qf=%{N}-%{V}-%{R}-%{ARCH}\n'

        # Container image is already updated + setup
        if [[ "${CONTAINER:-false}" != "true" ]]; then
            echo "Upgrading all packages"
            ooe.sh dnf update -y
        fi

        # Installed AND separetly querried/displayed
        CRITICAL_PKGS+=(\
            bcc
            bcc-devel
            conmon
            container-selinux
            containers-common
            crun
            golang
            kernel-core
            kernel-headers
            libseccomp
            podman
            runc
        )

        INSTALL_PACKAGES+=(\
            "${CRITICAL_PKGS[@]}"
            autoconf
            automake
            bash-completion
            bats
            bridge-utils
            btrfs-progs-devel
            bzip2
            containers-common
            device-mapper-devel
            emacs-nox
            file
            findutils
            fuse3
            fuse3-devel
            gcc
            git
            glib2-devel
            glibc-static
            gnupg
            go-md2man
            gpgme-devel
            iproute
            iptables
            jq
            libassuan-devel
            libcap-devel
            libmsi1
            libnet
            libnet-devel
            libnl3-devel
            libseccomp-devel
            libselinux-devel
            libtool
            libvarlink-util
            lsof
            make
            msitools
            nmap-ncat
            ostree
            ostree-devel
            pandoc
            procps-ng
            protobuf
            protobuf-c
            protobuf-c-devel
            protobuf-devel
            protobuf-python
            python
            python3-dateutil
            python3-psutil
            python3-pytoml
            selinux-policy-devel
            unzip
            vim
            which
            xz
            zip
        )
        # Some small differences between 30 and 31
        case "$OS_RELEASE_VER" in
            30)
                INSTALL_PACKAGES+=(\
                    atomic-registries \
                    golang-github-cpuguy83-go-md2man \
                    python2-future \
                    runc \
                )
                ;;
            31)
                INSTALL_PACKAGES+=(crun)
                ;;
            *)
                bad_os_id_ver ;;
        esac
        ;;
    ubuntu)
        if [[ "$CONTAINER" == "true" ]]; then
            echo "Ubuntu containers are not supported"
            bad_os_id_ver
        fi

        export DEBIAN_FRONTEND="noninteractive"
        INSTALL_COMMAND="apt-get -qq --yes install"
        LIST_COMMAND='dpkg-query --show --showformat=${Package}-${Version}-${Architecture}\n'
        CRITICAL_PKGS=(\
            bcc \
            containers-common \
            cri-o-runc \
            golang \
            libbpfcc \
            libbpfcc-dev \
            podman \
            libseccomp-dev \
        )
        # N/B: Travis also installs bcc-tools package, but this is not in the distro
        INSTALL_PACKAGES=(\
            "${CRITICAL_PKGS[@]}" \
            linux-headers-$(uname -r) \
        )
        # N/B: This provides different versions of bcc libraries and tools!
        # travis does:
        # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 91B31D79C30E5EE6
        # apt-add-repository https://repo.iovisor.org/apt/$(lsb_release -cs)
        apt-get -qq --yes update
        echo "Upgrading all packages"
        apt-get -qq --yes upgrade
        ;;
    *)
        bad_os_id_ver
        ;;
esac

if [[ "${#INSTALL_PACKAGES[@]}" -gt "0" ]]; then
    echo "Installing required packages (could take a handful of minutes)"
    ooe.sh $INSTALL_COMMAND ${INSTALL_PACKAGES[@]}
fi

if [[ "$OS_RELEASE_ID" == "fedora" ]] && [[ -r "/usr/libexec/podman/conmon" ]]
then
    echo "Warning: Working around podman 1.5 w/ embedded conmon."
    rm -vf '/usr/libexec/podman/conmon'
fi

# Some variables change after package install
source $(dirname $0)/lib.sh

echo "Building/Installing tooling"
ooe.sh make install.tools

echo "Names and versions of critical packages"
NOT_INSTALLED_RE='(package .+ is not installed)|(no packages found matching .+)'
$LIST_COMMAND ${CRITICAL_PKGS[@]} | sed -r -e "s/$NOT_INSTALLED_RE/ > > \0/" | sort

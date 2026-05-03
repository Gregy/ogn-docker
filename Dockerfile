################################################################################
# Builder stage: compile ogn-rf from pjalocha/ogn-rf-soapysdr.
# The prebuilt OGN ARM tarball expects the Pi VideoCore GPU FFT mailbox device,
# which isn't cleanly exposable to containers; building from source uses CPU FFT.
################################################################################
FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git make g++ \
        librtlsdr-dev libjpeg-dev libpng-dev libconfig-dev libfftw3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth 1 https://github.com/pjalocha/ogn-rf-soapysdr.git
WORKDIR /build/ogn-rf-soapysdr

# -DUSE_FFTW3 routes the heavy Inp_FFT through FFTW3. fftsg_float.cpp is still
# linked because some smaller transforms call cdft() unconditionally.
RUN g++ -Wall -Wno-misleading-indentation -O2 -DUSE_FFTW3 \
        -o ogn-rf ogn-rf.cc format.cpp serialize.cpp fftsg_float.cpp \
        -lpthread -lm -ljpeg -lpng -lconfig -lrt -lrtlsdr -lfftw3 -lfftw3f

################################################################################
# Runtime stage
################################################################################
FROM debian:bookworm-slim

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget \
        rtl-sdr libusb-1.0-0 librtlsdr0 \
        libconfig9 libpng16-16 libjpeg62-turbo \
        libfftw3-bin libfftw3-double3 libfftw3-single3 \
        build-essential libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# The prebuilt ogn-decode links against libjpeg.so.8; modern Debian ships
# libjpeg62-turbo. Build libjpeg8 from source per the wiki workaround.
RUN cd /tmp \
    && wget -qO- http://www.ijg.org/files/jpegsrc.v8d.tar.gz | tar -xz \
    && cd jpeg-8d \
    && ./configure --libdir=/usr/lib --prefix=/usr \
    && make -j"$(nproc)" \
    && make install \
    && cd / && rm -rf /tmp/jpeg-8d \
    && ldconfig \
    && apt-get -y purge build-essential libjpeg-dev \
    && apt-get -y autoremove

# Pull the official OGN tarball — we'll only use ogn-decode + getEGM.sh from it
WORKDIR /opt
RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64)            URL=http://download.glidernet.org/x64/rtlsdr-ogn-bin-x64-latest.tgz ;; \
        arm64)            URL=http://download.glidernet.org/arm64/rtlsdr-ogn-bin-arm64-latest.tgz ;; \
        arm|armhf|armv7)  URL=http://download.glidernet.org/arm/rtlsdr-ogn-bin-ARM-latest.tgz ;; \
        i386|386)         URL=http://download.glidernet.org/x86/rtlsdr-ogn-bin-x86-latest.tgz ;; \
        *) echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac \
    && wget --no-check-certificate -qO- "$URL" | tar -xz

WORKDIR /opt/rtlsdr-ogn

# Override the prebuilt ogn-rf with our source-built CPU-FFT version
COPY --from=builder /build/ogn-rf-soapysdr/ogn-rf /opt/rtlsdr-ogn/ogn-rf

RUN if [ -x ./getEGM.sh ]; then ./getEGM.sh || true; fi

COPY LKHC.conf /opt/rtlsdr-ogn/LKHC.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["LKHC.conf"]

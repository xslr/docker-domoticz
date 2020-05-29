FROM lsiobase/alpine:3.10

# set version label
ARG BUILD_DATE
ARG VERSION
ARG DOMOTICZ_COMMIT
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="saarg"

# environment settings
ENV HOME="/config"

# copy prebuilds
COPY patches/ /

RUN \
 echo "**** install build packages ****" && \
 apk add --no-cache --virtual=build-dependencies \
	argp-standalone \
	autoconf \
	automake \
	binutils \
	boost-dev \
	confuse-dev \
	curl-dev \
	doxygen \
	eudev-dev \
	g++ \
	gcc \
	git \
	gzip \
	jq \
	libcurl \
	libftdi1-dev \
	libressl-dev \
	libusb-compat-dev \
	libusb-dev \
	linux-headers \
	make \
	mosquitto-dev \
	musl-dev \
	pkgconf \
	sqlite-dev \
	tar \
	zlib-dev

RUN echo "**** install cmake 3.17 ****" && \
 cd /tmp && \
 wget https://github.com/Kitware/CMake/releases/download/v3.17.2/cmake-3.17.2.tar.gz && \
 tar xf cmake-3.17.2.tar.gz && \
 mv cmake-3.17.2 cmake-src && \
 cd cmake-src && \
 ./bootstrap --prefix=/usr && \
 make && \
 make install

RUN echo "**** install runtime packages ****" && \
 apk add --no-cache \
	boost \
	boost-system \
	boost-thread \
	curl \
	eudev-libs \
	iputils \
	libressl \
	lua5.3-dev \
	mosquitto \
	openssh \
	nodejs \
	npm \
	python3-dev \
	sudo && \
 echo "**** link libftdi libs ****" && \
 ln -s /usr/lib/libftdi1.so /usr/lib/libftdi.so && \
 ln -s /usr/lib/libftdi1.a /usr/lib/libftdi.a && \
 ln -s /usr/include/libftdi1/ftdi.h /usr/include/ftdi.h && \
 echo "**** build telldus-core ****" && \
 mkdir -p \
	/tmp/telldus-core && \
 tar xf /tmp/patches/telldus-core-2.1.2.tar.gz -C \
	/tmp/telldus-core --strip-components=1 && \
 curl -o /tmp/telldus-core/Doxyfile.in -L \
	https://raw.githubusercontent.com/telldus/telldus/master/telldus-core/Doxyfile.in && \
 cp /tmp/patches/Socket_unix.cpp /tmp/telldus-core/common/Socket_unix.cpp && \
 cp /tmp/patches/ConnectionListener_unix.cpp /tmp/telldus-core/service/ConnectionListener_unix.cpp && \
 cp /tmp/patches/CMakeLists.txt /tmp/telldus-core/CMakeLists.txt && \
 cd /tmp/telldus-core && \
 cmake -DBUILD_TDADMIN=false -DCMAKE_INSTALL_PREFIX=/tmp/telldus-core . && \
 make && \
 echo "**** configure telldus core ****" && \
 mv /tmp/telldus-core/client/libtelldus-core.so.2.1.2 /usr/lib/libtelldus-core.so.2.1.2 && \
 mv /tmp/telldus-core/client/telldus-core.h /usr/include/telldus-core.h && \
 ln -s /usr/lib/libtelldus-core.so.2.1.2 /usr/lib/libtelldus-core.so.2 && \
 ln -s /usr/lib/libtelldus-core.so.2 /usr/lib/libtelldus-core.so && \
 echo "**** build openzwave ****" && \
 git clone https://github.com/OpenZWave/open-zwave.git /tmp/open-zwave && \
 ln -s /tmp/open-zwave /tmp/open-zwave-read-only && \
 cd /tmp/open-zwave && \
 make && \
 make \
	instlibdir=usr/lib \
	pkgconfigdir="usr/lib/pkgconfig/" \
	PREFIX=/usr \
	sysconfdir=etc/openzwave \
 install

RUN echo "**** install cereal ****" && \
 cd /tmp && \
 git clone --depth=1 https://github.com/USCiLab/cereal.git && \
 cd cereal && mkdir build && cd build && \
 cmake -DCMAKE_INSTALL_PREFIX=/usr -DJUST_INSTALL_CEREAL=ON .. && \
 make && \
 make install && \
 cd / && \
 rm -rf /tmp/cereal

RUN cd /usr/lib && \
 ln -s lua5.3/liblua.a liblua5.3.a

RUN echo "**** build domoticz ****" && \
 if [ -z ${DOMOTICZ_COMMIT+x} ]; then \
	DOMOTICZ_COMMIT=$(curl -sX GET https://api.github.com/repos/domoticz/domoticz/commits/development \
	| jq -r '. | .sha'); \
 fi && \
 git clone https://github.com/domoticz/domoticz.git /tmp/domoticz && \
 cd /tmp/domoticz && \
 git checkout ${DOMOTICZ_COMMIT} && \
 git apply /tmp/patches/openzwave_include.patch && \
 cmake \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/var/lib/domoticz \
	-DOpenZWave=/usr/lib/libopenzwave.so \
	-DUSE_LUA_STATIC=ON \
	-DUSE_BUILTIN_MQTT=ON \
	-DUSE_BUILTIN_SQLITE=OFF \
	-DUSE_STATIC_BOOST=OFF \
	-DUSE_STATIC_LIBSTDCXX=OFF \
	-DUSE_STATIC_OPENZWAVE=OFF \
	# build jsoncpp as static lib
	-DBUILD_SHARED_LIBS=OFF \
	# fix build bug in mosquitto
	# https://github.com/eclipse/mosquitto/commit/4ab0f4bd3979fc196b2cec04a9298ecc7a38f62a
	-DWITH_BUNDLED_DEPS=ON \
	-Wno-dev && \
 make && \
 make install

RUN groupadd -r homebridge && \
 useradd --no-log-init --create-home -r -g homebridge homebridge && \
 groupadd -r zigbee2mqtt && \
 useradd --no-log-init --create-home --groups uucp -r -g zigbee2mqtt zigbee2mqtt

RUN echo "**** install zigbee2mqtt ****" && \
 git clone --depth=1 https://github.com/Koenkk/zigbee2mqtt.git /var/lib/zigbee2mqtt && \
 cd /var/lib/zigbee2mqtt && \
 rm -r ./data && \
 ln -s /config/zigbee2mqtt ./data && \
 chown -R zigbee2mqtt:zigbee2mqtt /var/lib/zigbee2mqtt && \
 su - zigbee2mqtt && \
 npm ci

RUN echo "**** install homebridge ****" && \
 npm install -g --unsafe-perm homebridge homebridge-config-ui-x homebridge-edomoticz

RUN echo "**** install BroadlinkRM2 plugin dependencies ****" && \
 git clone https://github.com/mjg59/python-broadlink.git /tmp/python-broadlink && \
 cd /tmp/python-broadlink && \
 git checkout 8bc67af6 && \
 pip3 install --no-cache-dir . && \
 pip3 install --no-cache-dir pyaes && \
 echo "**** determine runtime packages using scanelf ****" && \
 RUNTIME_PACKAGES="$( \
	scanelf --needed --nobanner /var/lib/domoticz/domoticz \
	| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
	| sort -u \
	| xargs -r apk info --installed \
	| sort -u \
	)" && \
 apk add --no-cache \
	$RUNTIME_PACKAGES && \
 echo "**** add abc to dialout and cron group ****" && \
 usermod -a -G 16,20 abc && \
 echo " **** cleanup ****" && \
 apk del --purge \
	build-dependencies && \
 rm -rf \
	/tmp/* \
	/usr/lib/libftdi* \
	/usr/include/ftdi.h

# copy local files
COPY root/ /

# ports
# don't bother with exposing ports. host networking is needed for homebridge

# volumes
VOLUME /config

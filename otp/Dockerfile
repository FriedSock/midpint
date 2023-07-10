#FROM ubuntu:22.04 as builder
FROM arm64v8/ubuntu:23.10

ARG CONCURRENCY

# set paths
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
ENV LD_LIBRARY_PATH /usr/local/lib:/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu:/lib32:/usr/lib32

# install deps
WORKDIR /usr/local/src/valhalla
COPY ./scripts/install-linux-deps.sh /usr/local/src/valhalla/scripts/install-linux-deps.sh
RUN bash /usr/local/src/valhalla/scripts/install-linux-deps.sh
RUN rm -rf /usr/local/src/valhalla/scripts/
RUN rm -rf /var/lib/apt/lists/*

# get the code into the right place and prepare to build it
RUN git clone https://github.com/valhalla/valhalla.git /usr/local/src/valhalla
RUN git checkout cbabe7cfbad2225090e4c006c778f1f0a7b3ec4e
RUN git submodule sync && git submodule update --init --recursive
RUN rm -rf build && mkdir build


# configure the build with symbols turned on so that crashes can be triaged
WORKDIR /usr/local/src/valhalla/build
RUN cmake .. -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER=gcc
RUN make all -j${CONCURRENCY:-$(nproc)}
COPY vendor/london_big.osm.pbf /var/otp/graphs/london/london.pbf
COPY config.json /usr/local/config.json
COPY ./valhalla/src/mjolnir/pbfgraphparser.cc /usr/local/src/valhalla/src/mjolnir/pbfgraphparser.cc
COPY ./valhalla/src/mjolnir/osmpbfparser.cc /usr/local/src/valhalla/src/mjolnir/osmpbfparser.cc
COPY ./valhalla/src/mjolnir/luatagtransform.cc /usr/local/src/valhalla/src/mjolnir/luatagtransform.cc
RUN make -j${CONCURRENCY:-$(nproc)}
RUN make install

# we wont leave the source around but we'll drop the commit hash we'll also keep the locales
WORKDIR /usr/local/src
RUN cd valhalla && echo "https://github.com/valhalla/valhalla/tree/$(git rev-parse HEAD)" > ../valhalla_version
RUN for f in valhalla/locales/*.json; do cat ${f} | python3 -c 'import sys; import json; print(json.load(sys.stdin)["posix_locale"])'; done > valhalla_locales
RUN rm -rf valhalla

COPY vendor/gtfs.zip /var/otp/graphs/london/gtfs.zip
RUN mkdir /var/gtfs
RUN mkdir /var/gtfs/london
RUN cd /var/gtfs/london && unzip /var/otp/graphs/london/gtfs.zip

RUN valhalla_ingest_transit -c /usr/local/config.json
RUN valhalla_convert_transit -c /usr/local/config.json

COPY vendor/london-big.osm.pbf /var/otp/graphs/london/london.pbf
# osmconvert ~/Downloads/england-latest.osm.pbf -b=-0.6633823712789136,51.233512521656195,0.2531707746918359,51.722144095352796  --out-pbf -o=london-big.osm.pbf
#
RUN valhalla_build_tiles -c /usr/local/config.json /var/otp/graphs/london/london.pbf

WORKDIR /usr/local/src/valhalla
RUN git clone https://github.com/valhalla/valhalla.git /usr/local/src/valhalla
RUN git checkout cbabe7cfbad2225090e4c006c778f1f0a7b3ec4e
RUN git submodule sync && git submodule update --init --recursive
RUN rm -rf build && mkdir build


# the binaries are huge with all the symbols so we strip them but keep the debug there if we need it
# RUN for f in valhalla_*; do objcopy --only-keep-debug $f $f.debug; done
# RUN tar -cvf valhalla.debug.tar valhalla_*.debug && gzip -9 valhalla.debug.tar
# RUN rm -f valhalla_*.debug
# RUN strip --strip-debug --strip-unneeded valhalla_* || true
# RUN strip /usr/local/lib/libvalhalla.a
# RUN strip /usr/lib/python3/dist-packages/valhalla/python_valhalla*.so

# FROM ubuntu:22.04 as runner
#
# COPY --from=builder /usr/local /usr/local
# COPY --from=builder /usr/lib/python3/dist-packages/valhalla/* /usr/lib/python3/dist-packages/valhalla/
#
# # we need to add back some runtime dependencies for binaries and scripts
# # install all the posix locales that we support
# RUN export DEBIAN_FRONTEND=noninteractive && apt update && \
#     apt install -y \
#       libcurl4 libczmq4 libluajit-5.1-2 \
#       libprotobuf-dev libsqlite3-0 libsqlite3-mod-spatialite libzmq5 zlib1g \
#       curl gdb locales parallel python3.10-minimal python3-distutils python-is-python3 \
#       spatialite-bin unzip wget && \
#     cat /usr/local/src/valhalla_locales | xargs -d '\n' -n1 locale-gen && \
#     rm -rf /var/lib/apt/lists/* && \
#     \
#     # python smoke test
#     python3 -c "import valhalla,sys; print(sys.version, valhalla)"
#
# RUN apt-get update > /dev/null && \
#       apt-get install -y \
#         curl jq unzip spatialite-bin
# COPY vendor/london.osm.pbf /var/otp/graphs/london/london.pbf
# COPY vendor/gtfs.zip /var/otp/graphs/london/gtfs.zip
# RUN mkdir /var/gtfs
# RUN mkdir /var/gtfs/london
# RUN cd /var/gtfs/london && unzip /var/otp/graphs/london/gtfs.zip
# COPY config.json config.json

# RUN cd /usr/local/bin && \
#   preserve="valhalla_service valhalla_build_tiles valhalla_build_config valhalla_build_admins valhalla_build_timezones valhalla_build_elevation valhalla_ways_to_edges valhalla_build_extract valhalla_export_edges valhalla_add_predicted_traffic valhalla_ingest_transit valhalla_convert_transit" && \
#   mv $preserve .. && \
#   for f in valhalla*; do rm $f; done && \
#   cd .. && mv $preserve ./bin
#
#
# COPY --from=builder /usr/local /usr/local
#
# COPY vendor/london.osm.pbf /var/otp/graphs/london/london.pbf
# COPY vendor/gtfs.zip /var/otp/graphs/london/gtfs.zip
# CMD ["valhalla_build_tiles"]



# FROM amazoncorretto:8
#
# ENV OTP_VERSION=1.5.0
#
# RUN yum install -y unzip
#
# ADD https://repo1.maven.org/maven2/org/opentripplanner/otp/$OTP_VERSION/otp-$OTP_VERSION-shaded.jar /usr/local/share/java/
#
# RUN ln -s otp-$OTP_VERSION-shaded.jar /usr/local/share/java/otp.jar
#
# COPY otp /usr/local/bin/
#
# RUN mkdir /var/otp
# RUN mkdir /var/otp/graphs
# RUN mkdir /var/otp/graphs/london
#
# COPY vendor/london.osm.pbf /var/otp/graphs/london/london.pbf
# COPY vendor/gtfs.zip /var/otp/graphs/london/gtfs.zip
# COPY build-config.json /var/otp/graphs/london/build-config.json
#
# ENV JAVA_OPTIONS=-Xmx10G
# RUN otp --build /var/otp/graphs/london
# ENV JAVA_OPTIONS=-Xmx1G
#
# CMD ["otp", "--router", "london", "--server"]




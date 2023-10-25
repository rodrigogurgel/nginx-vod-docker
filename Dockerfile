ARG NGINX_VERSION=1.25.1
ARG NGINX_VOD_MODULE_VERSION=1.32
ARG NGINX_AWS_AUTH_MODULE_VERSION=1.1
ARG NGINX_SECURE_TOKEN_MODULE_VERSION=1.5
ARG FFMPEG_VERSION=6.0

FROM alpine:3.18 as build-nginx
ARG NGINX_VERSION
ARG NGINX_VOD_MODULE_VERSION
ARG NGINX_AWS_AUTH_MODULE_VERSION
ARG NGINX_SECURE_TOKEN_MODULE_VERSION

RUN apk add --no-cache \
  build-base \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  libgcc \
  linux-headers \
  make \
  musl-dev \
  openssl \
  openssl-dev \
  pcre \
  pcre-dev \
  pkgconf \
  pkgconfig \
  zlib-dev

# Get nginx source.
RUN cd /tmp && \
  wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-vod-module source.
RUN cd /tmp && \
  wget https://github.com/kaltura/nginx-vod-module/archive/refs/tags/${NGINX_VOD_MODULE_VERSION}.tar.gz && \
  tar zxf ${NGINX_VOD_MODULE_VERSION}.tar.gz && \
  rm ${NGINX_VOD_MODULE_VERSION}.tar.gz

# Get nginx-aws-auth-module source.
RUN cd /tmp && \
  wget https://github.com/kaltura/nginx-aws-auth-module/archive/refs/tags/${NGINX_AWS_AUTH_MODULE_VERSION}.tar.gz && \
  tar zxf ${NGINX_AWS_AUTH_MODULE_VERSION}.tar.gz && \
  rm ${NGINX_AWS_AUTH_MODULE_VERSION}.tar.gz

# Get nginx-secure-token-module source.
RUN cd /tmp && \
  wget https://github.com/kaltura/nginx-secure-token-module/archive/refs/tags/${NGINX_SECURE_TOKEN_MODULE_VERSION}.tar.gz && \
  tar zxf ${NGINX_SECURE_TOKEN_MODULE_VERSION}.tar.gz && \
  rm ${NGINX_SECURE_TOKEN_MODULE_VERSION}.tar.gz

RUN cd /tmp/nginx-${NGINX_VERSION} && \
  ./configure \
    --prefix=/etc/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/etc/nginx/nginx.pid \
    --with-debug \
    --with-http_secure_link_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-file-aio \
    --with-http_mp4_module \
    --with-http_slice_module \
    --with-threads \
    --with-stream \
    --with-cc-opt='-O0 -g' \
    --add-module=../nginx-vod-module-${NGINX_VOD_MODULE_VERSION} \
    --add-module=../nginx-aws-auth-module-${NGINX_AWS_AUTH_MODULE_VERSION} \
    --add-module=../nginx-secure-token-module-${NGINX_SECURE_TOKEN_MODULE_VERSION}


RUN cd /tmp/nginx-${NGINX_VERSION} && \
   make && make install

# Build the FFmpeg-build image.
FROM alpine:3.18 as build-ffmpeg
ARG FFMPEG_VERSION
ARG PREFIX=/usr/local
ARG MAKEFLAGS="-j4"

RUN apk add --no-cache \
  build-base \
  coreutils \
  freetype-dev \
  lame-dev \
  libogg-dev \
  libass \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  openssl \
  openssl-dev \
  opus-dev \
  pkgconf \
  pkgconfig \
  rtmpdump-dev \
  wget \
  x264-dev \
  x265-dev \
  yasm

RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
RUN apk add --update fdk-aac-dev

# Get FFmpeg source.
RUN cd /tmp/ && \
  wget https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
  ./configure \
  --prefix=${PREFIX} \
  --enable-version3 \
  --enable-gpl \
  --enable-nonfree \
  --enable-small \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libtheora \
  --enable-libvorbis \
  --enable-libopus \
  --enable-libfdk-aac \
  --enable-libass \
  --enable-libwebp \
  --enable-librtmp \
  --enable-postproc \
  --enable-libfreetype \
  --enable-openssl \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --extra-libs="-lpthread -lm"

RUN cd tmp/ffmpeg-${FFMPEG_VERSION} && \
  make && make install && make distclean

# Cleanup.
RUN rm -rf /var/cache/* /tmp/*

# Build the release image.
FROM alpine:3.18

RUN apk add --no-cache \
  ca-certificates \
  gettext \
  openssl \
  pcre \
  lame \
  libogg \
  curl \
  libass \
  libvpx \
  libvorbis \
  libwebp \
  libtheora \
  opus \
  rtmpdump \
  x264-dev \
  x265-dev

COPY --from=build-nginx /etc/nginx /etc/nginx
COPY --from=build-ffmpeg /usr/local /usr/local
COPY --from=build-ffmpeg /usr/lib/libfdk-aac.so.2 /usr/lib/libfdk-aac.so.2

RUN apk --update add fuse alpine-sdk automake autoconf libxml2-dev fuse-dev curl-dev git bash;

ENV PATH "${PATH}:/etc/nginx/sbin"

EXPOSE 1935
EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
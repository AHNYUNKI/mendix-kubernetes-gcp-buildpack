# Dockerfile to create a Mendix Docker image based on either the source code or
# Mendix Deployment Archive (aka mda file)
#
# Author: Mendix Digital Ecosystems, digitalecosystems@mendix.com
# Version: v6.0.1
ARG ROOTFS_IMAGE=mendix-rootfs:app
ARG BUILDER_ROOTFS_IMAGE=mendix-rootfs:builder

# Build stage
FROM ${BUILDER_ROOTFS_IMAGE} AS builder

# Build-time variables
ARG BUILD_PATH=project
ARG DD_API_KEY

# Exclude the logfilter binary by default
ARG EXCLUDE_LOGFILTER=true

# Allow specification of alternative BLOBSTORE location and debugging
ARG BLOBSTORE
ARG BUILDPACK_XTRACE

# Copy project model/sources
COPY $BUILD_PATH /opt/mendix/build

# Use nginx supplied by the base OS
ENV NGINX_CUSTOM_BIN_PATH=/usr/sbin/nginx

# Set the user ID
ARG USER_UID=1001

# Copy start scripts
COPY scripts/startup.py scripts/vcap_application.json /opt/mendix/build/

# Each comment corresponds to the script line:
# 1. Create cache directory and directory for dependencies which can be shared
# 2. Set permissions for compilation scripts
# 3. Navigate to buildpack directory
# 4. Call compilation script
# 5. Remove temporary files
# 6. Create symlink for java prefs used by CF buildpack
# 7. Update ownership of /opt/mendix so that the app can run as a non-root user
# 8. Update permissions of /opt/mendix so that the app can run as a non-root user
RUN mkdir -p /tmp/buildcache/bust /tmp/cf-deps /var/mendix/build /var/mendix/build/.local &&\
    chmod +rx /opt/mendix/buildpack/compilation.py /opt/mendix/buildpack/buildpack/stage.py /opt/mendix/build/startup.py &&\
    cd /opt/mendix/buildpack &&\
    ./compilation.py /opt/mendix/build /tmp/buildcache /tmp/cf-deps 0 &&\
    rm -fr /tmp/buildcache /tmp/javasdk /tmp/opt /tmp/downloads /opt/mendix/buildpack/compilation.py /var/mendix &&\
    ln -s /opt/mendix/.java /opt/mendix/build &&\
    chown -R ${USER_UID}:0 /opt/mendix &&\
    chmod -R g=u /opt/mendix

FROM ${ROOTFS_IMAGE}
LABEL Author="Mendix Digital Ecosystems"
LABEL maintainer="digitalecosystems@mendix.com"

# Install Ruby if Datadog is detected
ARG DD_API_KEY
RUN if [ ! -z "$DD_API_KEY" ] ; then\
    microdnf update -y && \
    microdnf install -y ruby && \
    microdnf clean all && rm -rf /var/cache/yum \
    ; fi

# Set the home path
ENV HOME=/opt/mendix/build

# Add the buildpack modules
ENV PYTHONPATH "/opt/mendix/buildpack/lib/:/opt/mendix/buildpack/:/opt/mendix/buildpack/lib/python3.11/site-packages/"

# Set the user ID
ARG USER_UID=1001

USER ${USER_UID}

# Copy build artifacts from build container
COPY --from=builder /opt/mendix /opt/mendix

# Use nginx supplied by the base OS
ENV NGINX_CUSTOM_BIN_PATH=/usr/sbin/nginx

WORKDIR /opt/mendix/build

# Expose nginx port
ENV PORT 8080
EXPOSE $PORT

ENTRYPOINT ["/opt/mendix/build/startup.py"]

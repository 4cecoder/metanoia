# Dockerfile for Metanoia AppImage debugging
# Provides Fedora 38 environment with all debugging tools

FROM fedora:38

# Install debugging and analysis tools
RUN dnf install -y \
    binutils \
    gdb \
    strace \
    ltrace \
    valgrind \
    curl \
    file \
    elfutils \
    zlib \
    xorg-x11-server-Xvfb \
    squashfs-tools \
    && dnf clean all

# Create working directory
WORKDIR /metanoia-debug

# Set working directory
WORKDIR /metanoia-debug

# Copy debug wrapper into the image
COPY .opencode/docker/debug-wrapper.sh /usr/local/bin/debug-wrapper.sh
RUN chmod +x /usr/local/bin/debug-wrapper.sh

# Default command: run the debug wrapper
CMD ["/usr/local/bin/debug-wrapper.sh"]
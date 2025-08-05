FROM ubuntu:22.04

# Install necessary packages
RUN apt-get update && apt-get install -y \
    git \
    bash \
    zsh \
    curl \
    sudo \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for testing
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up git config for root (during build)
RUN git config --global user.email "test@example.com" && \
    git config --global user.name "Test User" && \
    git config --global init.defaultBranch main

# Create working directory
WORKDIR /workspace

# Copy the script to test
COPY gw.sh /workspace/gw.sh

# Copy test script
COPY test.sh /workspace/test.sh
RUN chmod +x /workspace/test.sh

# Switch to non-root user
USER testuser

# Set up git config for testuser
RUN git config --global user.email "test@example.com" && \
    git config --global user.name "Test User" && \
    git config --global init.defaultBranch main

# Set up test environment
RUN mkdir -p /home/testuser/test-repos

WORKDIR /home/testuser/test-repos

# Run tests by default
CMD ["/workspace/test.sh"]
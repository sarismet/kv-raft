FROM alpine:latest

# Install curl and bash, which are needed by the initialization script
RUN apk add --no-cache curl bash

# Copy the initialization script from the host's scripts directory into the image.
# The build context will be the project root, so this path is correct.
COPY ./docker-init-cluster.sh /init-cluster.sh

# Make the script executable
RUN chmod +x /init-cluster.sh

# Set the default command to run when the container starts.
# This will execute the script.
CMD ["/init-cluster.sh"] 
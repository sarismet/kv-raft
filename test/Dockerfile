FROM alpine:latest

# Install curl, bash, and jq for running the test scripts
RUN apk add --no-cache curl bash jq

# Create a working directory
WORKDIR /test

# Copy all test scripts
COPY . .

# Make all shell scripts executable
RUN chmod +x *.sh

# Create a script that runs tests at configurable intervals
RUN echo '#!/bin/bash' > /test/run_tests_loop.sh && \
    echo 'TEST_INTERVAL=${TEST_INTERVAL:-30}' >> /test/run_tests_loop.sh && \
    echo 'while true; do' >> /test/run_tests_loop.sh && \
    echo '  echo "🔄 Starting automated test run at $(date)"' >> /test/run_tests_loop.sh && \
    echo '  # Run tests without user interaction by answering "y" automatically' >> /test/run_tests_loop.sh && \
    echo '  echo "y" | ./run_all.sh' >> /test/run_tests_loop.sh && \
    echo '  echo "⏰ Waiting ${TEST_INTERVAL} seconds before next test run..."' >> /test/run_tests_loop.sh && \
    echo '  sleep ${TEST_INTERVAL}' >> /test/run_tests_loop.sh && \
    echo 'done' >> /test/run_tests_loop.sh && \
    chmod +x /test/run_tests_loop.sh

# Run the loop script
CMD ["/test/run_tests_loop.sh"] 
# Build stage
FROM python:3.12-slim-bullseye AS build

ARG REQUIREMENTS=requirements.txt
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    git \
    curl \
    wget \
    unzip \
    gnupg \
    libssl-dev \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libjpeg-dev \
    libopenjp2-7-dev \
    bsdmainutils \
    dnsutils \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Set up virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY $REQUIREMENTS requirements.txt ./
RUN pip install --no-cache-dir -U pip && \
    pip install --no-cache-dir -r requirements.txt

# Install Google Chrome
RUN wget -qO - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Nuclei
RUN wget https://github.com/projectdiscovery/nuclei/releases/download/v2.6.5/nuclei_2.6.5_linux_amd64.zip \
    && unzip nuclei_2.6.5_linux_amd64.zip \
    && mv nuclei /usr/local/bin/ \
    && rm nuclei_2.6.5_linux_amd64.zip \
    && git clone https://github.com/projectdiscovery/nuclei-templates.git /opt/nuclei-templates

# Install testssl.sh
RUN git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl.sh

# Install Snallygaster and TruffleHog
RUN pip install --no-cache-dir snallygaster trufflehog

# Final stage
FROM python:3.12-slim-bullseye

WORKDIR /home/spiderfoot

# Environment variables
ENV SPIDERFOOT_DATA /var/lib/spiderfoot
ENV SPIDERFOOT_LOGS /var/lib/spiderfoot/log
ENV SPIDERFOOT_CACHE /var/lib/spiderfoot/cache
ENV PATH="/opt/venv/bin:/usr/local/bin:$PATH"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libxslt1.1 \
    libjpeg62-turbo \
    libopenjp2-7 \
    bsdmainutils \
    dnsutils \
    coreutils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /sbin/nologin -d /home/spiderfoot -c "SpiderFoot User" spiderfoot \
    && mkdir -p $SPIDERFOOT_DATA $SPIDERFOOT_LOGS $SPIDERFOOT_CACHE \
    && chown spiderfoot:spiderfoot $SPIDERFOOT_DATA $SPIDERFOOT_LOGS $SPIDERFOOT_CACHE

# Copy application files, virtual environment, and additional tools
COPY --chown=spiderfoot:spiderfoot . .
COPY --from=build --chown=spiderfoot:spiderfoot /opt/venv /opt/venv
COPY --from=build --chown=spiderfoot:spiderfoot /usr/bin/google-chrome /usr/bin/google-chrome
COPY --from=build --chown=spiderfoot:spiderfoot /usr/local/bin/nuclei /usr/local/bin/nuclei
COPY --from=build --chown=spiderfoot:spiderfoot /opt/nuclei-templates /opt/nuclei-templates
COPY --from=build --chown=spiderfoot:spiderfoot /opt/testssl.sh /opt/testssl.sh

USER spiderfoot

EXPOSE 5001

# Health check
HEALTHCHECK --interval=60s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5001/ || exit 1

# Run the application
ENTRYPOINT ["python"]
CMD ["sf.py", "-l", "0.0.0.0:5001"]

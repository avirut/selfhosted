FROM node:18-alpine

RUN apk add --no-cache git
# RUN git clone --depth 1 --branch v3.0-beta5 https://gitdab.com/cadence/out-of-your-element.git /app
RUN git clone --depth 1 https://gitdab.com/cadence/out-of-your-element.git /app
WORKDIR /app
RUN npm i

RUN chmod +x scripts/setup.js

RUN mkdir -p /data
RUN touch /data/ooye.db && \
    mkdir -p /app/db && \
    ln -sf /data/ooye.db /app/db/ooye.db

VOLUME /data

CMD ["tail", "-f", "/dev/null"]
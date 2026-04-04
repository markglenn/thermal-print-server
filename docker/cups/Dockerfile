FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      cups \
      cups-filters \
      curl && \
    rm -rf /var/lib/apt/lists/*

COPY cupsd.conf /etc/cups/cupsd.conf
RUN echo "FileDevice Yes" >> /etc/cups/cups-files.conf
COPY setup-printers.sh /usr/local/bin/setup-printers.sh
RUN chmod +x /usr/local/bin/setup-printers.sh

EXPOSE 631

CMD ["setup-printers.sh"]

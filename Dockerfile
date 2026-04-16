FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEDEBUG=-all \
    WINEPREFIX=/home/steam/.wine \
    WINEARCH=win64 \
    STEAM_APP_ID=4129620

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wget curl ca-certificates gnupg \
      lib32gcc-s1 xvfb cabextract unzip tar \
      locales procps \
 && mkdir -pm755 /etc/apt/keyrings \
 && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
 && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
 && apt-get update \
 && apt-get install -y --install-recommends winehq-stable \
 && curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -o /usr/local/bin/winetricks \
 && chmod +x /usr/local/bin/winetricks \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 steam \
 && mkdir -p /home/steam/steamcmd /home/steam/windrose \
 && curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C /home/steam/steamcmd \
 && chown -R steam:steam /home/steam

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/steam
ENTRYPOINT ["/entrypoint.sh"]

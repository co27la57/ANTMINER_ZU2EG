#!/bin/sh
# Play Bad Apple!! on the Xvfb display (visible through VNC).
#   badapple            fullscreen
#   badapple --window   windowed, so the xfce panel stays visible
export DISPLAY=:1
export HOME=/root
export LD_LIBRARY_PATH=/usr/lib/arm-linux-gnueabihf:/lib/arm-linux-gnueabihf:/usr/lib
export XDG_RUNTIME_DIR=/tmp/xdg
VIDEO=/root/videos/badapple.mp4
MODE="$1"

mkdir -p /tmp/xdg && chmod 700 /tmp/xdg

# NOTE: --input-vo-keyboard=no is essential here.  With the default (yes) mpv
# grabs the keyboard through the X window and *pauses playback as soon as the
# window loses focus*, which in a headless VNC session happens immediately and
# leaves the video frozen on the first frame.
if /usr/bin/mpv --version >/dev/null 2>&1; then
    if [ "$MODE" = "--window" ]; then
        echo "Using mpv (windowed)"
        exec /usr/bin/mpv --vo=x11 --no-osc --no-input-cursor --input-vo-keyboard=no \
             --loop --hwdec=no --audio-device=null --autofit=60% --no-fullscreen \
             --keep-open=always --title="BadApple" "$VIDEO"
    fi
    echo "Using mpv (fullscreen)"
    exec /usr/bin/mpv --vo=x11 --really-quiet --fullscreen --no-terminal --loop \
         --hwdec=no --audio-device=null --no-osc --input-vo-keyboard=no \
         --keep-open=always "$VIDEO"
elif /usr/bin/mplayer -version >/dev/null 2>&1; then
    echo "Using mplayer"
    exec /usr/bin/mplayer -fs -vo x11 -nolirc -really-quiet -loop 0 -ao null "$VIDEO"
fi
echo "no working player"
exit 1

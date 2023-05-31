#!/usr/bin/env zsh

IMAGE=${1:?need docker image}
SERVICE=${2:?need systemd service}

SUDO=/usr/bin/sudo
DOCKER=/usr/bin/docker
GREP=/bin/grep
SYSTEMCTL=/bin/systemctl
AWK=/usr/bin/awk
XARGS=/usr/bin/xargs

output=$($DOCKER pull "$IMAGE")
exit_code=$?

IMAGE_WITHOUT_TAG=${IMAGE/:*/}
echo "Image without tag: $IMAGE_WITHOUT_TAG"

echo $output
echo $output | $GREP -q '^Status: Downloaded newer image for ' && $SUDO $SYSTEMCTL restart $SERVICE
echo "$DOCKER images | $GREP -- $IMAGE_WITHOUT_TAG | $GREP '<none>' | $AWK '{print $3}' | $XARGS $DOCKER rmi"
exit $exit_code

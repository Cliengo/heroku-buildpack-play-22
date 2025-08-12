#!/usr/bin/env bash

export_env_dir() {
  env_dir=$1
  whitelist_regex=${2:-''}
  blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH|JAVA_OPTS)$'}
  if [ -d "$env_dir" ]; then
    for e in $(ls "$env_dir"); do
      echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
      export "$e=$(cat "$env_dir/$e")"
    done
  fi
}

get_play_version() {
  local file=${1?"No file specified"}
  if [ ! -f "$file" ]; then
    return 0
  fi
  grep -P '.*-.*play[ \t]+[0-9\.]' "$file" | sed -E -e 's/[ \t]*-[ \t]*play[ \t]+([0-9A-Za-z\.]*).*/\1/'
}

check_compile_status() {
  if [ "${PIPESTATUS[*]}" != "0 0" ]; then
    echo " !     Failed to build Play! application"
    rm -rf "$CACHE_DIR/$PLAY_PATH"
    echo " !     Cleared Play! framework from cache"
    exit 1
  fi
}

download_play_official() {
  local playVersion=${1}
  local playTarFile=${2}
  local playZipFile="play-${playVersion}.zip"
  local playUrl="https://downloads.typesafe.com/play/${playVersion}/${playZipFile}"

  if [[ "$playVersion" == "1.4.5" ]]; then
    playUrl="https://github.com/Cliengo/heroku-buildpack-play/releases/download/v26/play-1.4.5.zip"
  elif [[ "$playVersion" > "1.6.0" ]]; then
    playUrl="https://github.com/playframework/play1/releases/download/${playVersion}/${playZipFile}"
  fi

  status=$(curl --retry 3 --silent --head -w %{http_code} -L "$playUrl" -o /dev/null)
  if [ "$status" != "200" ]; then
    echo "Could not locate: ${playUrl}"
    echo "Please check that the version ${playVersion} is correct in your conf/dependencies.yml"
    exit 1
  fi

  echo "Downloading ${playZipFile} from ${playUrl}"
  curl --retry 3 -s -O -L "$playUrl"

  # create tar file
  echo "Preparing binary package..."
  local playUnzipDir="tmp-play-unzipped/"
  mkdir -p "$playUnzipDir"
  unzip "$playZipFile" -d "$playUnzipDir" > /dev/null 2>&1

  PLAY_BUILD_DIR=$(find "$playUnzipDir" -name 'framework' -type d | sed 's/framework//')

  mkdir -p tmp/.play/framework/src/play

  cp -r "$PLAY_BUILD_DIR/framework/"* tmp/.play/framework
  cp -r "$PLAY_BUILD_DIR/modules" tmp/.play
  cp -r "$PLAY_BUILD_DIR/play" tmp/.play
  cp -r "$PLAY_BUILD_DIR/resources" tmp/.play

  mkdir -p build
  tar czf "$playTarFile" -C tmp/ .play > /dev/null 2>&1
  rm -rf tmp/
}

validate_play_version() {
  local playVersion=${1}
  if [ "$playVersion" == "1.4.0" ] || [ "$playVersion" == "1.3.2" ]; then
    echo "Unsupported version: $playVersion"
    echo "This version of Play! is incompatible with Linux. Upgrade to a newer version."
    exit 1
  elif [[ "$playVersion" =~ ^2.* ]]; then
    echo "Unsupported version: Play 2.x requires the Scala buildpack"
    exit 1
  fi
}

install_play() {
  local version=$1
  local tarFile="play-heroku.tar.gz"
  local url="https://s3.amazonaws.com/heroku-jvm-langpack-play/play-heroku-$version.tar.gz"

  validate_play_version "$version"

  echo "-----> Installing Play! $version..."

  if curl --retry 3 --silent --head -w %{http_code} -L "$url" -o /dev/null | grep -q 200; then
    curl --retry 3 -s --max-time 150 -L "$url" -o "$tarFile"
  else
    download_play_official "$version" "$tarFile"
  fi

  if [ ! -f "$tarFile" ]; then
    echo "-----> Error downloading Play! framework."
    exit 1
  fi

  if ! file "$tarFile" | grep -q gzip; then
    echo "Invalid Play! archive downloaded. Exiting."
    exit 1
  fi

  tar xzmf "$tarFile"
  rm "$tarFile"
  chmod +x "$PLAY_PATH/play"
  echo "Done installing Play!"
}

remove_play() {
  local buildDir=${1}
  local playVersion=${2}
  rm -rf "${buildDir}/tmp-play-unzipped"
  rm -f "${buildDir}/play-${playVersion}.zip"
}

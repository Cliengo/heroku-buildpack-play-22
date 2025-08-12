#!/usr/bin/env bash

indent() {
  while IFS= read -r line; do
    printf '       %s\n' "$line"
  done
}

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
  local playUrl="https://github.com/Cliengo/heroku-buildpack-play/releases/download/v26/play-1.4.5.zip"
  
  if [[ "$playVersion" > "1.6.0" ]]; then
    playUrl="https://github.com/playframework/play1/releases/download/${playVersion}/${playZipFile}"
  fi

  curl --retry 3 -s -O -L ${playUrl}

  # create tar file
  echo "Preparing binary package..." | indent
  local playUnzipDir="tmp-play-unzipped/"
  mkdir -p ${playUnzipDir}
  unzip ${playZipFile} -d ${playUnzipDir} > /dev/null 2>&1

  PLAY_BUILD_DIR=$(find -name 'framework' -type d | sed 's/framework//')

  mkdir -p tmp/.play/framework/src/play

  # Add Play! framework
  cp -r $PLAY_BUILD_DIR/framework/dependencies.yml tmp/.play/framework
  cp -r $PLAY_BUILD_DIR/framework/lib/             tmp/.play/framework
  cp -r $PLAY_BUILD_DIR/framework/play-*.jar       tmp/.play/framework
  cp -r $PLAY_BUILD_DIR/framework/pym/             tmp/.play/framework
  cp -r $PLAY_BUILD_DIR/framework/src/play/version tmp/.play/framework/src/play
  cp -r $PLAY_BUILD_DIR/framework/templates/       tmp/.play/framework

  # Add Play! core modules
  cp -r $PLAY_BUILD_DIR/modules    tmp/.play

  # Add Play! Linux executable
  cp -r $PLAY_BUILD_DIR/play  tmp/.play

  # Add Resources
  cp -r $PLAY_BUILD_DIR/resources tmp/.play

  # Run tar and remove tmp space
  if [ ! -d build ]; then
    mkdir build
  fi

  tar cvzf ${playTarFile} -C tmp/ .play > /dev/null 2>&1
  rm -fr tmp/
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


export_env_dir() {
  env_dir=$1
  whitelist_regex=${2:-''}
  blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH|JAVA_OPTS)$'}
  if [ -d "$env_dir" ]; then
    for e in $(ls "$env_dir"); do
      echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
      export "$e=$(cat "$env_dir/$e")"
      :
    done
  fi
}

get_play_version() {
  local file=${1?"No file specified"}

  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi

  # parse dependencies.yml for play version, example line: "- play 1.4.5"
  grep -P '.*-.*play[ \t]+[0-9\.]+' "$file" | sed -E -e 's/[ \t]*-[ \t]*play[ \t]+([0-9A-Za-z\.]*).*/\1/'
}

check_compile_status() {
  # check last two piped commands exit status (assumes usage in eval | sed)
  local arr=("${PIPESTATUS[@]}")
  for s in "${arr[@]}"; do
    if [ "$s" != "0" ]; then
      echo " !     Failed to build Play! application"
      exit 1
    fi
  done
}

install_openjdk() {
  # Simple stub that downloads and unpacks a JDK 1.8 from Azul or adoptopenjdk or similar
  # You can customize this to match your needs
  local java_version=$1
  local build_dir=$2
  local bin_dir=$3

  echo "Installing OpenJDK version $java_version..."

  JDK_DIR="$build_dir/.jdk"
  mkdir -p "$JDK_DIR"

  # For demo: download Azul Zulu JDK 8 Linux x64 tar.gz
  if [[ "$java_version" == "1.8" || "$java_version" == "8" ]]; then
    JDK_URL="https://javadl.oracle.com/webapps/download/AutoDL?BundleId=251398_0d8f12bc927a4e2c9f8568ca567db4ee"
  else
    echo "Unsupported Java version $java_version"
    exit 1
  fi

  # Download and extract
  curl -sL "$JDK_URL" | tar xz -C "$JDK_DIR" --strip-components=1
  echo "OpenJDK installed to $JDK_DIR"
}

install_play() {
  VER_TO_INSTALL=$1
  PLAY_URL="https://s3.amazonaws.com/heroku-jvm-langpack-play/play-heroku-$VER_TO_INSTALL.tar.gz"
  PLAY_TAR_FILE="play-heroku.tar.gz"

  validate_play_version "$VER_TO_INSTALL"

  echo "-----> Installing Play! $VER_TO_INSTALL....."

  status=$(curl --retry 3 --silent --head -L -w "%{http_code}" -o /dev/null "$PLAY_URL")

  if [ "$status" != "200" ]; then
    download_play_official "$VER_TO_INSTALL" "$PLAY_TAR_FILE"
  else
    curl --retry 3 -s --max-time 150 -L "$PLAY_URL" -o "$PLAY_TAR_FILE"
  fi

  if [ ! -f "$PLAY_TAR_FILE" ]; then
    echo "-----> Error downloading Play! framework. Please try again..."
    exit 1
  fi

  if ! file "$PLAY_TAR_FILE" | grep -q gzip; then
    error "Failed to install Play! framework or unsupported Play! framework version specified.
Please review Dev Center for a list of supported versions."
    exit 1
  fi

  tar xzmf "$PLAY_TAR_FILE"
  rm "$PLAY_TAR_FILE"
  chmod +x "$PLAY_PATH/play"
  echo "Done installing Play!" | indent
}



remove_play() {
  local build_dir=$1
  local play_version=$2

  rm -rf "${build_dir}/tmp-play-unzipped"
  rm -f "${build_dir}/play-${play_version}.zip"
}

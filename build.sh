#set -x
pushd `dirname $0` > /dev/null;DIR=`pwd -P`;popd > /dev/null
REPOSITORY=${1-digitalspacestudio}
PHP_VERSIONS="7.1 7.2 7.3 7.4 8.0 8.1 8.2"
NODE_VERSIONS="12 14 16 18"
ALL_NODE_VERSIONS=$(curl https://unofficial-builds.nodejs.org/download/release/ | pup 'a text{}' | grep -o '[0-9]\+.[0-9]\+.[0-9]\+' | sort --version-sort -r);
for PHP_VERSION in $PHP_VERSIONS; do
    exact_php_version=$(docker --log-level error run --rm  php:${PHP_VERSION}-fpm-alpine sh -c "php --version | grep -o '^PHP [0-9]\+\.[0-9]\+\.[0-9A-Za-z]\+' | grep -o '[0-9]\+\.[0-9]\+\.[0-9A-Za-z]\+'")
    php_major=$(echo $exact_php_version | awk -F. '{print $1}')
    php_minor=$(echo $exact_php_version | awk -F. '{print $2}')
    php_fix=$(echo $exact_php_version | awk -F. '{print $3}')
    for NODE_VERSION in $NODE_VERSIONS; do
        exact_node_version=$(echo "${ALL_NODE_VERSIONS}" | grep "^${NODE_VERSION}." | head -1)
        node_major=$(echo $exact_node_version | awk -F. '{print $1}')
        node_minor=$(echo $exact_node_version | awk -F. '{print $2}')
        node_fix=$(echo $exact_node_version | awk -F. '{print $3}')
        
        echo "
        docker --log-level error buildx build --push --platform linux/amd64,linux/arm64 $DOCKER_BUILD_PHP_ARGS \
        --build-arg PHP_VERSION=$PHP_VERSION \
        --build-arg NODE_VERSION=$exact_node_version \
        -t $REPOSITORY/php-node-alpine:$php_major.$php_minor.$php_fix-$node_major.$node_minor.$node_fix \
        -t $REPOSITORY/php-node-alpine:$php_major.$php_minor-$node_major.$node_minor \
        -t $REPOSITORY/php-node-alpine:$php_major.$php_minor-$node_major
        "
    done
    docker --log-level error rmi -f php:${PHP_VERSION}-fpm-alpine
done
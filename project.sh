#! /bin/bash

if ! (( "$OSTYPE" == "gnu-linux" )); then
  echo "docker-compose-lamp-stack-dev runs only on GNU/Linux operating system. Exiting..."
  exit
fi

###############################################################################
# 1.) Assign variables and create directory structure
###############################################################################

  #PROJECT_NAME is parent directory
  PROJECT_NAME=`echo ${PWD##*/}`
  PROJECT_UID=`id -u`
  PROJECT_GID=`id -g`

  PROJECT_AUTHOR=`git config user.name`
  if [ -z "${PROJECT_AUTHOR}" ]; then 
    echo "ALERT: git config user.name is not set!"
    exit
  fi
    
  PROJECT_EMAIL=`git config user.email`
  if [ -z "${PROJECT_EMAIL}" ]; then 
    echo "ALERT: git config user.email is not set!"
    exit
  fi

############################ CLEAN SUBROUTINE #################################

clean() {
  docker-compose stop
  docker system prune -af --volumes
  rm -rf node_modules \
    vendor \
    .cache \
    .config \
    .phpunit.cache \
    .yarn
} 

############################ START SUBROUTINE #################################

start() {

###############################################################################
# 2.) Generate very basic website if it doesn't exist
###############################################################################

  if [[ ! -d src ]] ; then

    # generate .git folder with initial commit
    rm -rf .git
    git init
    git add .
    git commit -m "feat: initial commit"

    # generate folder structure
    mkdir -p src/{js,src}
    mkdir -p tests/{spec,phpunit}
    mkdir -p docs

  fi

  if [[ ! -f src/index.php ]]; then
    touch src/index.php
    cat <<EOF> src/index.php
<?php
\$conn = new mysqli("mysql-database", "$PROJECT_NAME", "$PROJECT_NAME", "$PROJECT_NAME");

// check connection
if (mysqli_connect_errno()) {
  exit('Connect failed: '. mysqli_connect_error());
}

// SQL query
\$sql = "SHOW TABLES IN \`$PROJECT_NAME\`";

// perform the query and store the result
\$result = \$conn->query(\$sql);

// if the $result not False, and contains at least one row
if(\$result !== false) {
  // if at least one table in result
  if(\$result->num_rows > 0) {
    // traverse the $result and output the name of the table(s)
    while(\$row = \$result->fetch_assoc()) {
      echo '<br />'. \$row['Tables_in_database'];
    }
  }
  else echo 'There is no table in the database';
}
else echo 'Unable to check the database, error - '. \$conn->error;

\$conn->close();
?>
<?php phpinfo(); ?>
EOF
  fi

###############################################################################
# 3.) Generate configuration files
###############################################################################

  if [[ ! -f docker-compose.yml ]]; then
    touch docker-compose.yml
    cat <<EOF>docker-compose.yml
    version: "3.8"

    services:
      mysql-database:
        image: mariadb:latest
        volumes:
          - db_data:/var/lib/mysql
        environment:
          MYSQL_ROOT_PASSWORD: $PROJECT_NAME
          MYSQL_DATABASE:      $PROJECT_NAME
          MYSQL_USER:          $PROJECT_NAME
          MYSQL_PASSWORD:      $PROJECT_NAME
        ports:
          - 3306:3306

      php:
        image: php:7.4-apache
#        user: $PROJECT_UID:$PROJECT_GID
        depends_on: 
          - mysql-database
        command: >
            /bin/sh -c '
            docker-php-ext-install mysqli && exec docker-php-entrypoint apache2-foreground
            '
        volumes:
          - ./src:/var/www/html/
        ports:
          - 80:80

      composer:
        image: composer:latest
        user: $PROJECT_UID:$PROJECT_GID
        command: [ composer, install ]
        volumes:
          - .:/app
        environment:
          - COMPOSER_CACHE_DIR=/var/cache/composer

      node:
        image: node:alpine
        user: $PROJECT_UID:$PROJECT_GID
        working_dir: /home/node
        volumes:
          - .:/home/node
        environment:
          NODE_ENV: development

      phpcbf:
        image: php:7.4-fpm-alpine
        user: $PROJECT_UID:$PROJECT_GID
        working_dir: /app
        volumes:
          - .:/app
        entrypoint: vendor/bin/phpcbf

      phpcs:
        image: php:7.4-fpm-alpine
        user: $PROJECT_UID:$PROJECT_GID
        working_dir: /app
        volumes:
          - .:/app
        entrypoint: vendor/bin/phpcs

      phpdoc:
        image: phpdoc/phpdoc
        user: $PROJECT_UID:$PROJECT_GID
        volumes:
          - .:/data

      phpmyadmin:
        image: phpmyadmin/phpmyadmin
        environment:
          PMA_HOST: mysql-database
          PMA_PORT: 3306
          MYSQL_ROOT_PASSWORD: $PROJECT_NAME
        ports:
          - 8080:80

      phpunit:
        image: php:7.4-fpm-alpine
        user: $PROJECT_UID:$PROJECT_GID
        working_dir: /app
        volumes:
          - .:/app
        entrypoint: vendor/bin/phpunit


    volumes:
      db_data:
EOF
  fi

  if [[ ! -f phpunit.xml ]]; then
    touch phpunit.xml
    cat <<EOF> phpunit.xml
<?xml version="1.0" encoding="UTF-8"?>
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="https://schema.phpunit.de/9.5/phpunit.xsd"
         bootstrap="./vendor/autoload.php"
         cacheResultFile=".phpunit.cache/test-results"
         executionOrder="depends,defects"
         forceCoversAnnotation="true"
         beStrictAboutCoversAnnotation="true"
         beStrictAboutOutputDuringTests="true"
         beStrictAboutTodoAnnotatedTests="true"
         convertDeprecationsToExceptions="true"
         failOnRisky="true"
         failOnWarning="true"
         verbose="true">
    <testsuites>
        <testsuite name="default">
            <directory>./tests/phpunit</directory>
        </testsuite>
    </testsuites>

     <coverage cacheDirectory=".phpunit.cache/code-coverage"
              processUncoveredFiles="true">
        <include>
            <directory suffix=".php">./src</directory>
        </include>
    </coverage>
</phpunit>
EOF
  fi

  if [[ ! -f phpcs.xml ]]; then
    touch phpcs.xml
    cat <<EOF> phpcs.xml
<?xml version="1.0"?>
  <ruleset xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
  name="$PROJECT_NAME" 
  xsi:noNamespaceSchemaLocation="https://raw.githubusercontent.com/squizlabs/PHP_CodeSniffer/master/phpcs.xsd">
  
    <file>src/</file>
    <file>tests/</file>
       
    <exclude-pattern>*\.(scss|css|js)$</exclude-pattern>    
    
    <rule ref="PEAR">
    </rule>
    
  </ruleset>
EOF
  fi

  if [[ ! -f .gitignore ]]; then
    touch .gitignore
    cat <<EOF> .gitignore
# Ignore docs folder
/docs/

# Ignore node_modules folder
/node_modules/

# Ignore vendor folder
/vendor/

# Ignore .cache folder
/.cache/

# Ignore .config folder
/.config/

# Ignore .phpunit.cache folder
/.phpunit.cache/

# Ignore .yarn folder
/.yarn/

# Ignore .lock files
*.lock
EOF
  fi

  if [[ ! -f composer.json ]]; then
    touch composer.json
    cat <<EOF> composer.json
{
    "name": "$PROJECT_AUTHOR/$PROJECT_NAME",
    "description": "docker-compose-lamp-stack-dev project",
    "version": "1.0.0",
    "type": "wordpress-theme",
    "license": "GPL-2.0-or-later",
    "authors": [
      {
        "name": "$PROJECT_AUTHOR",
        "email": "$PROJECT_EMAIL"
      }
    ],
    "autoload": {
      "psr-4": { "": "src/"}
    }
}
EOF
  fi

  if [[ ! -f package.json ]]; then
    touch package.json
    cat <<EOF> package.json
{
    "name": "$PROJECT_NAME",
    "description": "docker-compose-lamp-stack-dev project",
    "version": "1.0.0",
    "license": "GPL-2.0-or-later",
    "author": "$PROJECT_AUTHOR <$PROJECT_EMAIL>",
    "private": true
}
EOF
  fi

###############################################################################
# 4.) Install dependencies
###############################################################################

#PHP

  docker-compose run composer
  docker-compose run composer composer require --dev phpunit/phpunit
  docker-compose run composer composer require --dev squizlabs/php_codesniffer
  docker-compose run composer composer require --dev wp-coding-standards/wpcs
  docker-compose run composer config allow-plugins.dealerdirect/phpcodesniffer-composer-installer  true
  docker-compose run composer composer require --dev dealerdirect/phpcodesniffer-composer-installer    
  docker-compose run composer -- dump-autoload

#JavaScript

  docker-compose run node yarn install
  docker-compose run node yarn global add ynpx

  docker-compose up -d

}

"$1"

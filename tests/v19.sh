#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
db_password=${TKL_TEST_DB_PASS:?TKL_TEST_DB_PASS is required}
base=https://localhost
email=admin@example.invalid
cookie=/tmp/tkl-bookstack-cookie.$$
page=/tmp/tkl-bookstack-page.$$
headers=/tmp/tkl-bookstack-headers.$$
policy=/tmp/tkl-bookstack-policy.$$
scheduler=/tmp/tkl-bookstack-scheduler.$$

cleanup() {
    rm -f -- "$cookie" "$page" "$headers" "$policy" "$scheduler"
}
trap cleanup EXIT

csrf_token() {
    sed -n 's/.*name="_token" value="\([^"]*\)".*/\1/p' "$1" |
        head -n 1
}

redirect_location() {
    sed -n 's/^[Ll]ocation: \(.*\)\r$/\1/p' "$1" | tail -n 1
}

systemctl --quiet is-active apache2.service mariadb.service postfix.service \
    cron.service multi-user.target
systemctl --quiet is-enabled apache2.service mariadb.service postfix.service \
    cron.service
apache2ctl -t
apache2ctl -M 2>/dev/null | grep -q ' rewrite_module '
grep -Fxq 'VERSION_CODENAME=trixie' /etc/os-release
grep -Eq '^turnkey-bookstack-19\.0' /etc/turnkey_version

version=$(< /var/www/bookstack/version)
commit=$(git -c safe.directory=/var/www/bookstack \
    -C /var/www/bookstack rev-parse HEAD)
[[ $version == v26.05.4 ]]
[[ $commit == cec78b1bcf096a74bf0a79fae3f884dc1d0803e4 ]]
git -c safe.directory=/var/www/bookstack -C /var/www/bookstack \
    describe --tags --exact-match |
    grep -Fxq "$version"
/usr/local/sbin/bookstack-update --verify-installed >/dev/null
composer --working-dir=/var/www/bookstack check-platform-reqs --no-dev
php_version=$(php --version | head -n 1)
[[ $php_version == 'PHP 8.4.'* ]]
for module in curl dom gd mbstring mysqli pdo_mysql xml zip; do
    php -m | grep -Fxiq "$module"
done

curl --insecure --fail --silent --show-error \
    --cookie-jar "$cookie" "$base/login" >"$page"
token=$(csrf_token "$page")
[[ -n $token ]]
curl --insecure --silent --show-error \
    --cookie "$cookie" --cookie-jar "$cookie" \
    --data-urlencode "_token=$token" \
    --data-urlencode "email=$email" \
    --data-urlencode "password=$app_password" \
    --dump-header "$headers" --output "$page" "$base/login"
grep -q '^HTTP/.* 302' "$headers"
curl --insecure --fail --silent --show-error \
    --cookie "$cookie" "$base/" >"$page"
grep -q 'Logout' "$page"
grep -q 'Admin' "$page"

curl --insecure --fail --silent --show-error \
    --cookie "$cookie" "$base/create-book" >"$page"
token=$(csrf_token "$page")
[[ -n $token ]]
book_name="TurnKey v19 acceptance book $$"
book_description="BookStack database round trip $$"
curl --insecure --silent --show-error \
    --cookie "$cookie" --cookie-jar "$cookie" \
    --data-urlencode "_token=$token" \
    --data-urlencode "name=$book_name" \
    --data-urlencode "description_html=<p>$book_description</p>" \
    --dump-header "$headers" --output "$page" "$base/books"
grep -q '^HTTP/.* 302' "$headers"
book_url=$(redirect_location "$headers")
[[ $book_url == "$base/books/"* ]]
curl --insecure --fail --silent --show-error \
    --cookie "$cookie" "$book_url" >"$page"
grep -Fq "$book_name" "$page"
grep -Fq "$book_description" "$page"

curl --insecure --silent --show-error \
    --cookie "$cookie" --dump-header "$headers" --output "$page" \
    "$book_url/create-page"
grep -q '^HTTP/.* 302' "$headers"
draft_url=$(redirect_location "$headers")
[[ $draft_url == "$book_url/draft/"* ]]
curl --insecure --fail --silent --show-error \
    --cookie "$cookie" "$draft_url" >"$page"
token=$(csrf_token "$page")
[[ -n $token ]]
page_name="TurnKey v19 acceptance page $$"
page_content="BookStack page content round trip $$"
curl --insecure --silent --show-error \
    --cookie "$cookie" --cookie-jar "$cookie" \
    --data-urlencode "_token=$token" \
    --data-urlencode "name=$page_name" \
    --data-urlencode "html=<p>$page_content</p>" \
    --dump-header "$headers" --output "$page" "$draft_url"
grep -q '^HTTP/.* 302' "$headers"
page_url=$(redirect_location "$headers")
[[ $page_url == "$book_url/page/"* ]]
curl --insecure --fail --silent --show-error \
    --cookie "$cookie" "$page_url" >"$page"
grep -Fq "$page_name" "$page"
grep -Fq "$page_content" "$page"

MYSQL_PWD=$db_password mariadb --user=root --batch --skip-column-names \
    bookstack --execute \
    "SELECT CONCAT(b.name, '|', p.name) FROM entities b JOIN entities p ON p.book_id=b.id JOIN entity_page_data pd ON pd.page_id=p.id WHERE b.type='book' AND p.type='page' AND b.name='$book_name' AND p.name='$page_name' AND pd.draft=0" |
    grep -Fxq "$book_name|$page_name"
turnkey-artisan migrate:status --no-interaction >/dev/null
grep -Fxq '* * * * * www-data /usr/local/bin/turnkey-artisan schedule:run --no-interaction >/dev/null 2>&1' \
    /etc/cron.d/bookstack
stat -c '%U:%G %a' /etc/cron.d/bookstack | grep -Fxq 'root:root 644'
runuser --user www-data -- /usr/local/bin/turnkey-artisan \
    schedule:run --no-interaction >"$scheduler"

dpkg-query -W adminer webmin-apache webmin-mysql webmin-phpini postfix \
    >/dev/null
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12321/ >/dev/null
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12322/ >/dev/null
ss -ltn | grep -Eq '127\.0\.0\.1:25[[:space:]]'

before="$(dpkg-query -W -f='${Version}' php-cli)|$(dpkg-query -W -f='${Version}' mariadb-server)|$(dpkg-query -W -f='${Version}' composer)"
apt-get update >/dev/null
for package in php-cli mariadb-server composer; do
    apt-cache policy "$package" >"$policy"
    candidate=$(awk '/Candidate:/ {print $2}' "$policy")
    [[ -n $candidate && $candidate != '(none)' ]]
    grep -Eq 'trixie|deb13' "$policy"
done
after="$(dpkg-query -W -f='${Version}' php-cli)|$(dpkg-query -W -f='${Version}' mariadb-server)|$(dpkg-query -W -f='${Version}' composer)"
[[ $after == "$before" ]]
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
! grep -Rqi bookworm /etc/apt/sources.list /etc/apt/sources.list.d

update_check=$(/usr/local/sbin/bookstack-update --check)
grep -Fxq "current_version=$version" <<<"$update_check"
grep -Fxq "current_commit=$commit" <<<"$update_check"
grep -Fxq "candidate_version=$version" <<<"$update_check"
grep -Fxq "candidate_commit=$commit" <<<"$update_check"
grep -Fxq 'update_available=no' <<<"$update_check"

cat >"$result" <<EOF
package_source=Official BookStack stable channel v26.05.4, signed tag bb71d0f5e539cd853381125a86772813e73aee3d and commit $commit; PHP, MariaDB, Apache, Composer and extensions from Debian Trixie
installed_version=BookStack $version ($commit); $php_version; mariadb-server $(dpkg-query -W -f='${Version}' mariadb-server); composer $(dpkg-query -W -f='${Version}' composer)
runtime_checks=normal init; Apache, MariaDB, Postfix and cron supervision; firstboot administrator HTTPS login; authenticated book and page create-read round trip; direct MariaDB persistence and Laravel migration status; scheduler cron contract and artisan invocation; Adminer and Webmin HTTPS endpoints
updater_command=bookstack-update --check
updater_result=pinned signing key accepted the current tag; official stable candidate matched installed v26.05.4 and commit $commit; no files or packages changed
updater_channel=https://source.bookstackapp.com/bookstack.git release branch, restricted to an annotated release tag signed by BookStack fingerprint 98F8536570C9A3745BFA8BAF116094FE15AE65C0
integrity_evidence=Git tag signature verified against the pinned BookStack upstream key; tag object and release commit matched the build pins; Composer lock platform requirements passed; APT accepted signed Trixie metadata; no Bookworm source remained
EOF

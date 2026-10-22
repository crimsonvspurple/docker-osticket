<?php

// Add the PHP 8.4 return types osTicket v1.18.4 added, without replacing
// the installed tree or touching the database. Safe to run more than once.

$root = $argv[1] ?? '/www/osticket';
$failed = false;

function patch_file(string $path, array $replacements): void
{
    global $failed;
    if (!is_file($path)) {
        fwrite(STDERR, "missing {$path}\n");
        $failed = true;
        return;
    }
    $src = file_get_contents($path);
    $orig = $src;
    foreach ($replacements as [$from, $to]) {
        if ($to !== '' && str_contains($src, $to)) {
            continue;
        }
        $count = 0;
        $src = str_replace($from, $to, $src, $count);
        if ($count === 0 && $to !== '') {
            fwrite(STDERR, "pattern not found in {$path}: ".strtok($from, "\n")."\n");
            $failed = true;
        }
    }
    if ($src === $orig) {
        echo "unchanged {$path}\n";
        return;
    }
    file_put_contents($path, $src);
    echo "patched {$path}\n";
}

$util = [
    ['function getIterator() {', 'function getIterator(): Traversable {'],
    ['function count($mode=COUNT_NORMAL) {', 'function count($mode=COUNT_NORMAL): int {'],
    ['function offsetGet($offset) {', 'function offsetGet($offset): mixed {'],
    [
        "    function offsetSet(\$offset, \$value) {\n        if (\$offset === null)\n            return \$this->storage[] = \$value;",
        "    function offsetSet(\$offset, \$value): void {\n        if (\$offset === null) {\n            \$this->storage[] = \$value;\n            return;\n        }",
    ],
    ['function offsetExists($offset) {', 'function offsetExists($offset): bool {'],
    ['function offsetUnset($offset) {', 'function offsetUnset($offset): void {'],
];

$orm = [
    ['function getIterator() {', 'function getIterator(): Traversable {'],
    ['function getIterator($iterator=false) {', 'function getIterator($iterator=false): Traversable {'],
    ['function count() {', 'function count(): int {'],
    ['function count($mode=COUNT_NORMAL) {', 'function count($mode=COUNT_NORMAL): int {'],
    ['function offsetGet($field) {', 'function offsetGet($field): mixed {'],
    ['function offsetGet($offset) {', 'function offsetGet($offset): mixed {'],
    ['function offsetSet($field, $what) {', 'function offsetSet($field, $what): void {'],
    ['function offsetSet($a, $b) {', 'function offsetSet($a, $b): void {'],
    ['function offsetExists($field) {', 'function offsetExists($field): bool {'],
    ['function offsetExists($offset) {', 'function offsetExists($offset): bool {'],
    ['function offsetUnset($field) {', 'function offsetUnset($field): void {'],
    ['function offsetUnset($a) {', 'function offsetUnset($a): void {'],
    [
        "    function rewind() {\n        \$this->eoi = false;",
        "    function rewind(): void {\n        \$this->eoi = false;",
    ],
    [
        "    function key() {\n        return \$this->key;",
        "    function key(): mixed {\n        return \$this->key;",
    ],
    [
        "    function valid() {\n        if (!isset(\$this->eoi))",
        "    function valid(): bool {\n        if (!isset(\$this->eoi))",
    ],
    [
        "    function current() {\n        if (\$this->eoi) return false;",
        "    function current(): mixed {\n        if (\$this->eoi) return false;",
    ],
    [
        "    function next() {\n        try {\n            \$cbk = \$this->callback;",
        "    function next(): void {\n        try {\n            \$cbk = \$this->callback;",
    ],
];

$message = [
    ['function getIterator() {', 'function getIterator(): Traversable {'],
];

$bootstrap = [
    ["        if (defined('E_STRICT')) # 5.4.0\n            \$error_reporting &= ~E_STRICT;\n", ''],
    ["ini_set('display_errors', 1);", "ini_set('display_errors', 0);"],
    ["ini_set('display_startup_errors', 1);", "ini_set('display_startup_errors', 0);"],
];

$attachment = [
    [
        'function count($lang=false) { return count($this->getSeparates($lang)); }',
        'function count($lang=false): int { return count($this->getSeparates($lang)); }',
    ],
];

patch_file("{$root}/include/class.util.php", $util);
patch_file("{$root}/include/class.orm.php", $orm);
patch_file("{$root}/include/class.message.php", $message);
patch_file("{$root}/include/class.attachment.php", $attachment);
patch_file("{$root}/bootstrap.php", $bootstrap);

exit($failed ? 1 : 0);

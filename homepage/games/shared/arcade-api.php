<?php
// arcade-api.php — shared state for the Learn wing (profiles + stars) on the road trip Pi.
// State lives in /var/www/state/arcade.json (mount a writable volume there, same as bingo).
// Actions: state | setprofiles | award
// Games call this directly; games/shared/players.js wraps the profiles/award parts.

header('Content-Type: application/json');
header('Cache-Control: no-store');

$STATE_DIR  = '/var/www/state';
$STATE_FILE = $STATE_DIR . '/arcade.json';

$AVATARS = ['🦊','🐻','🐸','🐝','🦁','🐵','🐰','🐼'];

function freshState() {
  return [
    'rev'      => 0,
    'profiles' => [],   // [{id, name, avatar, level}]
    'stars'    => []     // {profileId: totalStars}
  ];
}

$action = isset($_GET['action']) ? $_GET['action'] : 'state';
$body   = json_decode(file_get_contents('php://input'), true);
if (!is_array($body)) { $body = []; }

if (!is_dir($STATE_DIR)) { @mkdir($STATE_DIR, 0777, true); }
$h = @fopen($STATE_FILE, 'c+');
if (!$h) {
  http_response_code(500);
  echo json_encode(['ok' => false, 'err' => 'cannot open state file — check that /var/www/state is mounted and writable by www-data']);
  exit;
}
flock($h, LOCK_EX);
$raw = stream_get_contents($h);
$st  = $raw ? json_decode($raw, true) : null;
$dirty = false;
if (!is_array($st) || !isset($st['profiles']) || !isset($st['stars'])) {
  $st = freshState();
  $dirty = true;
}

$err = null;
switch ($action) {

  case 'state':
    break;

  case 'setprofiles':
    $profiles = isset($body['profiles']) && is_array($body['profiles']) ? $body['profiles'] : null;
    if ($profiles === null || count($profiles) > 8) {
      $err = 'bad request';
    } else {
      $clean = [];
      foreach ($profiles as $p) {
        if (!isset($p['id']) || !isset($p['name'])) { continue; }
        $clean[] = [
          'id'     => substr((string)$p['id'], 0, 40),
          'name'   => substr((string)$p['name'], 0, 24),
          'avatar' => in_array(isset($p['avatar']) ? $p['avatar'] : '', $AVATARS) ? $p['avatar'] : $AVATARS[0],
          'level'  => in_array(isset($p['level']) ? $p['level'] : '', ['toddler','k','3rd']) ? $p['level'] : 'k'
        ];
      }
      $st['profiles'] = $clean;
      $st['rev']++;
      $dirty = true;
    }
    break;

  case 'award':
    $pid = isset($body['profileId']) ? substr((string)$body['profileId'], 0, 40) : '';
    $n   = isset($body['stars']) ? (int)$body['stars'] : 1;
    if ($pid === '' || $n < 1 || $n > 20) {
      $err = 'bad request';
    } else {
      $found = false;
      foreach ($st['profiles'] as $p) { if ($p['id'] === $pid) { $found = true; break; } }
      if (!$found) {
        $err = 'unknown profile';
      } else {
        if (!isset($st['stars'][$pid])) { $st['stars'][$pid] = 0; }
        $st['stars'][$pid] += $n;
        $st['rev']++;
        $dirty = true;
      }
    }
    break;

  default:
    $err = 'unknown action';
}

if ($dirty) {
  rewind($h);
  ftruncate($h, 0);
  fwrite($h, json_encode($st));
  fflush($h);
}
flock($h, LOCK_UN);
fclose($h);

echo json_encode([
  'ok'    => $err === null,
  'err'   => $err,
  'state' => [
    'rev'      => $st['rev'],
    'profiles' => $st['profiles'],
    'stars'    => $st['stars'],
    'avatars'  => $AVATARS
  ]
]);

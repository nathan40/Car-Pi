<?php
// bingo-api.php — shared-state Minnesota Car Bingo for the road trip Pi.
// State lives in /var/www/state/bingo.json (mount a writable volume there).
// Actions: state | claim | mark | newgame | reset
// Feel free to edit $POOL below — the game page always uses the server's list.

header('Content-Type: application/json');
header('Cache-Control: no-store');

$STATE_DIR  = '/var/www/state';
$STATE_FILE = $STATE_DIR . '/bingo.json';

$POOL = [
  ['🦌','Deer'],       ['🐄','Cow'],         ['🐴','Horse'],      ['🚜','Tractor'],
  ['🌽','Corn Field'], ['🌾','Hay Field'],   ['🦃','Turkey'],     ['🐿️','Squirrel'],
  ['🦅','Eagle'],      ['🦆','Loon'],        ['🦋','Butterfly'],  ['🐶','Dog'],
  ['🌊','Lake'],       ['🛥️','Boat'],        ['🛶','Canoe'],      ['🌲','Pine Trees'],
  ['🌻','Sunflowers'], ['🌉','Bridge'],      ['⛪','Church'],     ['⛽','Gas Station'],
  ['🍦','Ice Cream'],  ['🚻','Rest Stop'],   ['🏕️','Camping'],    ['📫','Mailbox'],
  ['🇺🇸','Flag'],       ['🛑','Stop Sign'],   ['🚦','Stoplight'],  ['🚧','Road Work'],
  ['🚛','Semi Truck'], ['🚐','Camper'],      ['🚌','Bus'],        ['🏍️','Motorcycle'],
  ['🚂','Train'],      ['✈️','Plane'],       ['🚓','Police Car'], ['🚒','Fire Truck']
];

$LINES = [];
for ($r = 0; $r < 4; $r++) { $LINES[] = [$r*4, $r*4+1, $r*4+2, $r*4+3]; }
for ($c = 0; $c < 4; $c++) { $LINES[] = [$c, $c+4, $c+8, $c+12]; }
$LINES[] = [0, 5, 10, 15];
$LINES[] = [3, 6, 9, 12];

function dealCard($poolSize) {
  $idx = range(0, $poolSize - 1);
  shuffle($idx);
  return array_slice($idx, 0, 16);
}

function freshGame($claims, $rev) {
  global $POOL;
  $g = [
    'rev'    => $rev + 1,
    'status' => 'playing',
    'winner' => -1,
    'claims' => $claims,
    'cards'  => [],
    'marks'  => []
  ];
  for ($p = 0; $p < 4; $p++) {
    $g['cards'][] = dealCard(count($POOL));
    $g['marks'][] = array_fill(0, 16, false);
  }
  return $g;
}

$action = isset($_GET['action']) ? $_GET['action'] : 'state';
$device = isset($_GET['device']) ? substr((string)$_GET['device'], 0, 40) : '';
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
if (!is_array($st) || !isset($st['cards']) || !isset($st['claims'])) {
  $st = freshGame([null, null, null, null], 0);
  $dirty = true;
}

$err = null;
switch ($action) {

  case 'state':
    break;

  case 'claim':
    $p = isset($body['player']) ? (int)$body['player'] : -1;
    if ($p < 0 || $p > 3 || $device === '') {
      $err = 'bad request';
    } elseif ($st['claims'][$p] !== null && $st['claims'][$p] !== $device) {
      $err = 'taken';
    } else {
      $st['claims'][$p] = $device;
      $st['rev']++;
      $dirty = true;
    }
    break;

  case 'mark':
    $p = isset($body['player']) ? (int)$body['player'] : -1;
    $t = isset($body['tile'])   ? (int)$body['tile']   : -1;
    if ($p < 0 || $p > 3 || $t < 0 || $t > 15) {
      $err = 'bad request';
    } elseif ($st['status'] !== 'playing') {
      $err = 'paused';
    } elseif ($st['claims'][$p] !== $device) {
      $err = 'notyours';
    } else {
      $st['marks'][$p][$t] = !$st['marks'][$p][$t];
      $st['rev']++;
      $dirty = true;
      if ($st['marks'][$p][$t]) {
        foreach ($LINES as $line) {
          $full = true;
          foreach ($line as $i) {
            if (!$st['marks'][$p][$i]) { $full = false; break; }
          }
          if ($full) {
            $st['status'] = 'paused';
            $st['winner'] = $p;
            break;
          }
        }
      }
    }
    break;

  case 'newgame':
    $st = freshGame($st['claims'], $st['rev']);
    $dirty = true;
    break;

  case 'reset':
    $st = freshGame([null, null, null, null], $st['rev']);
    $dirty = true;
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

$players = [];
for ($p = 0; $p < 4; $p++) {
  $players[] = [
    'claimed' => $st['claims'][$p] !== null,
    'mine'    => $st['claims'][$p] !== null && $st['claims'][$p] === $device
  ];
}

echo json_encode([
  'ok'    => $err === null,
  'err'   => $err,
  'state' => [
    'rev'     => $st['rev'],
    'status'  => $st['status'],
    'winner'  => $st['winner'],
    'players' => $players,
    'cards'   => $st['cards'],
    'marks'   => $st['marks'],
    'pool'    => $POOL
  ]
]);

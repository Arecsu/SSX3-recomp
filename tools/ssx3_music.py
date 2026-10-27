#!/usr/bin/env python3
"""SSX 3 interactive music: dump a song's Pathfinder map (.mpf), its events
and its loop bank, with timings in beats from data/config/music.inf.

    python3 tools/ssx3_music.py <SSX3 folder> list
    python3 tools/ssx3_music.py <SSX3 folder> song <name or mpf> [--nodes] [--events]
    python3 tools/ssx3_music.py <SSX3 folder> check

<SSX3 folder> holds data/audio/music*.big and data/config/music.inf.
'check' compares every song's slice length with its BPM and its loop bank
with PhrasesPerBank / PhraseAlign (see docs/MUSIC.md for what they mean).
Formats: Pathfinder v4 'PFDx' (little-endian on Xbox), EA SCHl streams,
EA BNK v5 ('BNKl') loop banks with 'PT' sound headers.
"""
import os
import re
import struct
import sys


# ---- BIGF archives ---------------------------------------------------------

def big_entries(path):
    with open(path, 'rb') as f:
        h = f.read(16)
        if h[:4] != b'BIGF':
            raise ValueError(path + ': not a BIGF archive')
        n = struct.unpack('>I', h[8:12])[0]
        out = []
        for _ in range(n):
            off, size = struct.unpack('>II', f.read(8))
            name = b''
            while True:
                c = f.read(1)
                if c in (b'', b'\0'):
                    break
                name += c
            out.append((name.decode('latin1'), off, size))
    return out


class Game:
    def __init__(self, root):
        self.root = root
        self.files = {}
        for big in ('music.big', 'music2.big'):
            p = os.path.join(root, 'data', 'audio', big)
            if os.path.exists(p):
                for name, off, size in big_entries(p):
                    self.files[name.split('\\')[-1].lower()] = (p, off, size)
        self.songs = parse_music_inf(os.path.join(root, 'data', 'config', 'music.inf'))

    def read(self, name):
        p, off, size = self.files[name.lower()]
        with open(p, 'rb') as f:
            f.seek(off)
            return f.read(size)


# ---- music.inf -----------------------------------------------------------------

DEFAULTS = {'BPM': 120.0, 'BeatsPerMeasure': 4, 'MeasuresPerBar': 2, 'PhrasesPerBank': 4,
            'BeatsPerPhrase': 8, 'PhraseAlign': 16, 'DUCKTOLOOPS': 1}


def parse_music_inf(path):
    songs = []
    cur = None
    for line in open(path, encoding='latin1'):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        m = re.match(r'\[(.+)\]$', line)
        if m:
            cur = {'name': m.group(1), 'LOOPDATA': [], 'CATEGORY': []}
            songs.append(cur)
            continue
        m = re.match(r'(\w+)\s*=\s*"?([^"]*)"?$', line)
        if m and cur is not None:
            k, v = m.group(1), m.group(2)
            key = next((d for d in DEFAULTS if d.lower() == k.lower()), k.upper() if k.upper() in (
                'PATHDATA', 'MUSDATA', 'LOOPDATA', 'TITLE', 'ARTIST', 'CATEGORY', 'SONGBIG') else k)
            if key in ('LOOPDATA', 'CATEGORY'):
                cur[key].append(v)
            else:
                cur[key] = v
    out = {}
    for s in songs:
        if 'PATHDATA' not in s:
            continue
        for k, d in DEFAULTS.items():
            s[k] = type(d)(s.get(k, d))
        out[s['name'].lower()] = s
    return out


# ---- Pathfinder v4 ------------------------------------------------------------

class Mpf:
    """PFDx version 4 (SSX 3, NFS Underground 2): nodes, events, sample table."""

    def __init__(self, d):
        self.d = d
        if d[:4] != b'xDFP':
            raise ValueError('not a little-endian PFDx file')
        self.version, self.subversion = d[4], d[5]
        self.n_tracks, self.n_sections, self.n_events = d[0xd], d[0xe], d[0xf]
        self.n_routers, self.n_vars = d[0x10], d[0x11]
        self.n_nodes = self.u16(0x12)
        self.node_offs = [self.u16(0x20 + i * 2) * 4 for i in range(self.n_nodes)]
        last = self.node_offs[-1]
        ev_table = last + 0x10 + self.node_branch_count(last) * 4
        self.event_offs = [self.u16(ev_table + i * 2) * 4 for i in range(self.n_events)]
        last = self.event_offs[-1]
        after = last + 0x10 + self.event_action_count(last) * 0x10
        after += self.n_routers * 4
        self.tracks_table = self.u32(after) * 4
        self.samples_table = self.tracks_table + (self.n_tracks + 1) * 4
        end = self.u32(self.tracks_table + self.n_tracks * 4) * 4
        self.n_samples = (end - self.samples_table) // 8
        self.track_start = [(self.u32(self.tracks_table + i * 4) * 4 - self.samples_table) // 8
                            for i in range(self.n_tracks)]

    def u16(self, o):
        return struct.unpack_from('<H', self.d, o)[0]

    def u32(self, o):
        return struct.unpack_from('<I', self.d, o)[0]

    def be32(self, o):
        return struct.unpack_from('>I', self.d, o)[0]

    def node_branch_count(self, o):
        return (self.be32(o + 4) >> 20) & 0xF

    def event_action_count(self, o):
        return (self.be32(o + 0xc) >> 8) & 0x3F

    def node(self, i):
        o = self.node_offs[i]
        w0, w1, w2 = self.u32(o), self.u32(o + 4), self.u32(o + 8)
        branches = []
        for k in range(self.node_branch_count(o)):
            b = self.u32(o + 0x10 + k * 4)
            branches.append({'to': b >> 16, 'hi': (b >> 8) & 0xFF, 'lo': b & 0xFF})
        # the sample field is 1-based: 0 (or 0xFFFF) = no audio (a junction)
        smp = w0 & 0xFFFF
        return {'sample': None if smp in (0, 0xFFFF) else smp - 1, 'kind': w1 >> 24, 'word2': w2,
                'branches': branches}

    def sample(self, i):
        o = self.samples_table + i * 8
        return self.u32(o), self.u32(o + 4)          # offset (x0x80 / bank<<16|sound), ms

    def event(self, i):
        o = self.event_offs[i]
        acts = []
        for j in range(self.event_action_count(o)):
            w = [self.u32(o + 0x10 + j * 16 + k * 4) for k in range(4)]
            acts.append(decode_action(w))
        return acts


def decode_action(w):
    mask, track = w[0] >> 24, w[0] & 0xFF
    typ = (w[2] >> 8) & 0xFF
    v = w[3]
    if typ == 4:
        tgt = v & 0xFFFF
        if v == 0x01000000:
            text = 'stop'
        elif tgt >= 0xFFE0:
            text = 'return to register %d' % (0xFFF0 - tgt)
        else:
            text = 'go to node %d' % tgt
    elif typ == 0xA:
        text = 'store position in register %d' % (v >> 16)
    elif typ == 2:
        text = 'wait %d ms' % v
    elif typ == 6:
        text = 'fade over %d ms to %d' % (v >> 16, v & 0x7F)
    else:
        text = 'type %#x value %08x' % (typ, v)
    return 'track %d: %s%s' % (track, text, '' if mask == 0xF1 else ' [mask %#x]' % mask)


# ---- loop banks (EA BNK v5) ----------------------------------------------------

def bnk_sounds(b):
    """Durations (ms) of every sound in a BNKl bank, from its PT headers."""
    out = []
    for m in re.finditer(b'PT\x07\x00', b):
        p, tags = m.start() + 4, {}
        while p < len(b):
            k = b[p]
            p += 1
            if k == 0xFF:
                break
            if k in (0xFC, 0xFD, 0xFE):
                continue
            n = b[p]
            p += 1
            tags[k] = int.from_bytes(b[p:p + n], 'big')
            p += n
        rate = tags.get(0x84, 22050)
        out.append({'ms': tags.get(0x85, 0) * 1000.0 / rate, 'rate': rate,
                    'channels': tags.get(0x82, 1), 'codec': tags.get(0xA0)})
    return out


# ---- commands -------------------------------------------------------------------

def find_song(g, name):
    n = name.lower()
    if n in g.songs:
        return g.songs[n]
    for s in g.songs.values():
        if s['PATHDATA'].lower() in (n, n + '.mpf') or s.get('TITLE', '').lower() == n:
            return s
    raise SystemExit('no song ' + name)


def slice_beats(g, s):
    m = Mpf(g.read(s['PATHDATA']))
    beat = 60000.0 / s['BPM']
    end = m.track_start[1] if m.n_tracks > 1 else m.n_samples
    lens = [round(m.sample(i)[1] / beat, 2) for i in range(end)]
    return m, lens


def cmd_list(g):
    for s in sorted(g.songs.values(), key=lambda s: s['name'].lower()):
        print('%-12s %-28s BPM %-7g %s %s' % (s['name'], s.get('TITLE', ''), s['BPM'], s['PATHDATA'],
                                           ' '.join(s['LOOPDATA'])))


def cmd_song(g, name, nodes, events):
    s = find_song(g, name)
    m, lens = slice_beats(g, s)
    print('%s: %s by %s' % (s['name'], s.get('TITLE', '?'), s.get('ARTIST', '?')))
    print('music.inf: BPM %g, BeatsPerMeasure %d, MeasuresPerBar %d, BeatsPerPhrase %d, PhrasesPerBank %d, '
          'PhraseAlign %d, DUCKTOLOOPS %d' % (s['BPM'], s['BeatsPerMeasure'], s['MeasuresPerBar'],
                                              s['BeatsPerPhrase'], s['PhrasesPerBank'], s['PhraseAlign'],
                                              s['DUCKTOLOOPS']))
    print('mpf: version %d.%d, %d tracks (samples from %s), %d sections, %d events, %d nodes, %d samples'
          % (m.version, m.subversion, m.n_tracks, m.track_start, m.n_sections, m.n_events, m.n_nodes,
             m.n_samples))
    hist = {}
    for x in lens:
        hist[x] = hist.get(x, 0) + 1
    print('main track slices (beats at this BPM):', dict(sorted(hist.items(), key=lambda kv: -kv[1])[:4]))
    for lf in s['LOOPDATA']:
        if lf.lower() in g.files:
            snd = bnk_sounds(g.read(lf))
            beat = 60000.0 / s['BPM']
            print('loop bank %s: %d sounds; beats each: %s; %d Hz, %d ch' % (
                lf, len(snd), [round(x['ms'] / beat, 2) for x in snd][:4] + ['...'] +
                [round(x['ms'] / beat, 2) for x in snd][-2:], snd[0]['rate'], snd[0]['channels']))
    if events:
        print('\nevents (the game fires them by number; see docs/MUSIC.md):')
        for i in range(m.n_events):
            acts = m.event(i)
            if acts:
                print('  %2d: %s' % (i, '; '.join(acts)))
    if nodes:
        print('\nnodes (what plays, then: next node [lo..hi of the 0-127 control value]):')
        for i in range(m.n_nodes):
            n = m.node(i)
            if n['sample'] is None:
                what = 'junction'
            else:
                trk = max(t for t in range(m.n_tracks) if m.track_start[t] <= n['sample'])
                what = 'track %d sample %d (%d ms)' % (trk + 1, n['sample'], m.sample(n['sample'])[1])
            br = ', '.join('%d [%d..%d]' % (b['to'], b['lo'], b['hi']) for b in n['branches']) or 'end'
            print('  %4d %-32s -> %s' % (i, what, br))


def cmd_check(g):
    for s in sorted(g.songs.values(), key=lambda s: s['name'].lower()):
        if s['PATHDATA'].lower() not in g.files:
            continue
        m, lens = slice_beats(g, s)
        main = max(set(lens), key=lens.count)
        notes = []
        licensed = s.get('ADDTOFE', '0') == '1'
        if not licensed:
            notes.append('menu/ambient track (not cut to a beat grid)')
        elif abs(main - s['BeatsPerMeasure']) > 0.05 and abs(main - s['BeatsPerMeasure'] / 2) > 0.05:
            notes.append('BPM looks wrong: slices are %.2f beats at BPM %g, true BPM ~%.1f' % (
                main, s['BPM'], s['BPM'] * s['BeatsPerMeasure'] / main))
        for lf in s['LOOPDATA'] if licensed else []:
            if lf.lower() in g.files:
                snd = bnk_sounds(g.read(lf))
                phrases = (len(snd) - 2) // s['PhraseAlign']
                if s['PhrasesPerBank'] - 1 > phrases:
                    notes.append('(harmless) PhrasesPerBank %d > %d phrase(s) in %s' % (
                        s['PhrasesPerBank'], phrases, lf))
        print('%-12s %s' % (s['name'], '; '.join(notes) if notes else 'ok'))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = Game(argv[1])
    if argv[2] == 'list':
        cmd_list(g)
    elif argv[2] == 'song' and len(argv) > 3:
        cmd_song(g, argv[3], '--nodes' in argv, '--events' in argv)
    elif argv[2] == 'check':
        cmd_check(g)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

<!-- src/lib/components/terminal/EmbeddedTerminal.svelte -->
<script lang="ts">
  import '@xterm/xterm/css/xterm.css';
  import { onMount, onDestroy } from 'svelte';
  import { terminalStore } from '$lib/stores/terminal.svelte';

  interface Props {
    tabId: string;
  }

  let { tabId }: Props = $props();

  let containerEl: HTMLDivElement | undefined = $state();
  let xtermInstance: import('@xterm/xterm').Terminal | undefined;
  let fitAddon: import('@xterm/addon-fit').FitAddon | undefined;
  let resizeObserver: ResizeObserver | undefined;
  let childProcess: { write: (data: string) => Promise<void>; kill: () => Promise<void> } | undefined;
  let inputBuffer = '';
  let isTauri = false;

  function isTauriEnv(): boolean {
    return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
  }

  async function initTerminal(): Promise<void> {
    if (containerEl === undefined) return;

    const { Terminal } = await import('@xterm/xterm');
    const { FitAddon } = await import('@xterm/addon-fit');
    const { WebLinksAddon } = await import('@xterm/addon-web-links');
    const { SearchAddon } = await import('@xterm/addon-search');

    const term = new Terminal({
      cursorBlink: true,
      cursorStyle: 'bar',
      fontFamily: "'JetBrains Mono', 'Fira Code', 'SF Mono', 'Menlo', 'Consolas', monospace",
      fontSize: 13,
      lineHeight: 1.35,
      letterSpacing: 0,
      theme: {
        background: '#0d1117',
        foreground: '#c9d1d9',
        cursor: '#58a6ff',
        cursorAccent: '#0d1117',
        selectionBackground: 'rgba(56, 139, 253, 0.3)',
        selectionForeground: undefined,
        black: '#484f58',
        red: '#ff7b72',
        green: '#3fb950',
        yellow: '#d29922',
        blue: '#58a6ff',
        magenta: '#bc8cff',
        cyan: '#39d2c0',
        white: '#c9d1d9',
        brightBlack: '#6e7681',
        brightRed: '#ffa198',
        brightGreen: '#56d364',
        brightYellow: '#e3b341',
        brightBlue: '#79c0ff',
        brightMagenta: '#d2a8ff',
        brightCyan: '#56d4dd',
        brightWhite: '#f0f6fc',
      },
      scrollback: 5000,
      allowTransparency: true,
      convertEol: true,
    });

    const fit = new FitAddon();
    fitAddon = fit;
    term.loadAddon(fit);
    term.loadAddon(new WebLinksAddon());
    term.loadAddon(new SearchAddon());

    term.open(containerEl);

    requestAnimationFrame(() => {
      fit.fit();
    });

    xtermInstance = term;
    isTauri = isTauriEnv();

    if (isTauri) {
      await spawnTauriShell(term);
    } else {
      startMockShell(term);
    }

    resizeObserver = new ResizeObserver(() => {
      requestAnimationFrame(() => {
        fit.fit();
      });
    });
    resizeObserver.observe(containerEl);
  }

  async function spawnTauriShell(term: import('@xterm/xterm').Terminal): Promise<void> {
    try {
      const { Command } = await import('@tauri-apps/plugin-shell');

      const command = Command.create('sh', ['-i']);

      command.stdout.on('data', (data: string) => {
        term.write(data);
        terminalStore.appendScrollback(tabId, data);
      });

      command.stderr.on('data', (data: string) => {
        term.write(data);
        terminalStore.appendScrollback(tabId, data);
      });

      command.on('close', (payload: { code: number; signal: number | null }) => {
        term.write(`\r\n\x1b[90m[Process exited with code ${payload.code}]\x1b[0m\r\n`);
        childProcess = undefined;
      });

      command.on('error', (error: string) => {
        term.write(`\r\n\x1b[31m[Error: ${error}]\x1b[0m\r\n`);
      });

      const child = await command.spawn();
      childProcess = {
        write: (data: string) => child.write(data),
        kill: () => child.kill(),
      };

      term.onData((data: string) => {
        if (childProcess !== undefined) {
          childProcess.write(data);
        }
      });
    } catch (err) {
      term.write(`\x1b[31mFailed to spawn shell: ${(err as Error).message}\x1b[0m\r\n`);
      startMockShell(term);
    }
  }

  function startMockShell(term: import('@xterm/xterm').Terminal): void {
    const hostname = 'bizforge@osa';
    let cwd = '~';
    const history: string[] = [];
    let historyIndex = -1;

    function writePrompt(): void {
      term.write(`\x1b[38;5;245m${hostname}\x1b[0m:\x1b[38;5;111m${cwd}\x1b[0m$ `);
    }

    term.write('\x1b[38;5;245m╭──────────────────────────────────────────────╮\x1b[0m\r\n');
    term.write('\x1b[38;5;245m│\x1b[0m  BizForge Embedded Terminal                  \x1b[38;5;245m│\x1b[0m\r\n');
    term.write('\x1b[38;5;245m│\x1b[0m  \x1b[38;5;242mSimulated shell (browser mode)\x1b[0m              \x1b[38;5;245m│\x1b[0m\r\n');
    term.write('\x1b[38;5;245m│\x1b[0m  \x1b[38;5;242mConnect the backend for full terminal.\x1b[0m      \x1b[38;5;245m│\x1b[0m\r\n');
    term.write('\x1b[38;5;245m╰──────────────────────────────────────────────╯\x1b[0m\r\n\r\n');
    writePrompt();

    term.onData((data: string) => {
      const code = data.charCodeAt(0);

      if (code === 13) {
        term.write('\r\n');
        const cmd = inputBuffer.trim();
        inputBuffer = '';
        historyIndex = -1;

        if (cmd.length === 0) {
          writePrompt();
          return;
        }

        history.unshift(cmd);
        if (history.length > 100) history.pop();

        const output = executeMockCommand(cmd);
        if (output !== null) {
          term.write(output);
          if (!output.endsWith('\r\n')) term.write('\r\n');
        }

        const cdMatch = cmd.match(/^cd\s+(.+)/);
        if (cdMatch !== null) {
          const target = cdMatch[1].trim();
          if (target === '~' || target === '$HOME') cwd = '~';
          else if (target === '..') {
            const parts = cwd.split('/').filter(Boolean);
            parts.pop();
            cwd = parts.length === 0 ? '~' : parts.join('/');
          } else if (target.startsWith('/')) cwd = target;
          else cwd = cwd === '~' ? `~/${target}` : `${cwd}/${target}`;
          terminalStore.updateCwd(tabId, cwd);
        }

        writePrompt();
      } else if (code === 127) {
        if (inputBuffer.length > 0) {
          inputBuffer = inputBuffer.slice(0, -1);
          term.write('\b \b');
        }
      } else if (code === 3) {
        inputBuffer = '';
        term.write('^C\r\n');
        writePrompt();
      } else if (data === '\x1b[A') {
        if (history.length > 0 && historyIndex < history.length - 1) {
          historyIndex++;
          clearLine(term);
          inputBuffer = history[historyIndex];
          writePrompt();
          term.write(inputBuffer);
        }
      } else if (data === '\x1b[B') {
        if (historyIndex > 0) {
          historyIndex--;
          clearLine(term);
          inputBuffer = history[historyIndex];
          writePrompt();
          term.write(inputBuffer);
        } else if (historyIndex === 0) {
          historyIndex = -1;
          clearLine(term);
          inputBuffer = '';
          writePrompt();
        }
      } else if (code === 12) {
        term.clear();
        writePrompt();
      } else if (code >= 32) {
        inputBuffer += data;
        term.write(data);
      }
    });
  }

  function clearLine(term: import('@xterm/xterm').Terminal): void {
    term.write('\x1b[2K\r');
  }

  function executeMockCommand(cmd: string): string | null {
    const parts = cmd.split(/\s+/);
    const base = parts[0];

    switch (base) {
      case 'help':
        return [
          '\x1b[1mAvailable commands:\x1b[0m',
          '  help          Show this help message',
          '  echo <text>   Print text',
          '  date          Show current date/time',
          '  whoami        Show current user',
          '  hostname      Show hostname',
          '  uname         Show system info',
          '  pwd           Print working directory',
          '  ls            List directory contents',
          '  cd <dir>      Change directory',
          '  clear         Clear terminal',
          '  env           Show environment variables',
          '  uptime        Show uptime',
          '  bizforge      Show BizForge info',
          '',
          '\x1b[38;5;242mNote: This is a simulated shell. Connect the backend for a real terminal.\x1b[0m',
        ].join('\r\n');

      case 'echo':
        return parts.slice(1).join(' ');

      case 'date':
        return new Date().toString();

      case 'whoami':
        return 'bizforge';

      case 'hostname':
        return 'osa';

      case 'uname':
        return 'BizForge OSA v1.0.0 (Simulated)';

      case 'pwd':
        return terminalStore.activeTab?.cwd ?? '~';

      case 'ls': {
        const items = [
          '\x1b[1;34magents/\x1b[0m',
          '\x1b[1;34mworkflows/\x1b[0m',
          '\x1b[1;34mskills/\x1b[0m',
          '\x1b[1;34mdocuments/\x1b[0m',
          '\x1b[38;5;114mSYSTEM.md\x1b[0m',
          '\x1b[38;5;114mconfig.toml\x1b[0m',
          '\x1b[38;5;114m.env\x1b[0m',
        ];
        return items.join('  ');
      }

      case 'cd':
        return null;

      case 'clear':
        return null;

      case 'env':
        return [
          'BIZFORGE_VERSION=1.0.0',
          'BIZFORGE_MODE=desktop',
          'SHELL=/bin/sh',
          'USER=bizforge',
          'HOME=~/.bizforge',
          'TERM=xterm-256color',
        ].join('\r\n');

      case 'uptime':
        return `up ${Math.floor(Math.random() * 48)} hours, ${Math.floor(Math.random() * 60)} minutes`;

      case 'bizforge':
        return [
          '',
          '  \x1b[1;38;5;208mBizForge\x1b[0m \x1b[38;5;245mv1.0.0\x1b[0m',
          '  \x1b[38;5;242mAI-powered business automation platform\x1b[0m',
          '',
          '  Status:  \x1b[32mRunning\x1b[0m',
          '  Agents:  \x1b[36m0 active\x1b[0m',
          '  Backend: \x1b[33mMock mode\x1b[0m',
          '',
        ].join('\r\n');

      default:
        return `\x1b[31mcommand not found: ${base}\x1b[0m\r\n\x1b[38;5;242mType 'help' for available commands.\x1b[0m`;
    }
  }

  onMount(() => {
    initTerminal();
  });

  onDestroy(() => {
    resizeObserver?.disconnect();
    if (childProcess !== undefined) {
      childProcess.kill().catch(() => {});
    }
    xtermInstance?.dispose();
  });
</script>

<div class="et-container" bind:this={containerEl}></div>

<style>
  .et-container {
    flex: 1;
    width: 100%;
    height: 100%;
    background: #0d1117;
    overflow: hidden;
  }

  .et-container :global(.xterm) {
    padding: 12px 8px;
    height: 100%;
  }

  .et-container :global(.xterm-viewport::-webkit-scrollbar) {
    width: 6px;
  }

  .et-container :global(.xterm-viewport::-webkit-scrollbar-track) {
    background: transparent;
  }

  .et-container :global(.xterm-viewport::-webkit-scrollbar-thumb) {
    background: rgba(255, 255, 255, 0.15);
    border-radius: 3px;
  }

  .et-container :global(.xterm-viewport::-webkit-scrollbar-thumb:hover) {
    background: rgba(255, 255, 255, 0.25);
  }
</style>

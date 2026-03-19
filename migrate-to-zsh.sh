#!/bin/bash
# Migrate bash -> zsh on Arch Linux
# Run as your normal user. Handles root separately at the end.

set -e

echo "=== Installing zsh and extras ==="
sudo pacman -S --needed --noconfirm zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting

echo ""
echo "=== Migrating bash history ==="
# Convert .bash_history to zsh extended_history format
# Format: : epoch:0;command
if [[ -f ~/.bash_history ]]; then
    # Deduplicate while preserving order, convert to zsh format
    # Use current timestamp as a baseline (zsh just needs *something*)
    ts=$(date +%s)
    awk -v ts="$ts" '!seen[$0]++ { printf ": %d:0;%s\n", ts++, $0 }' \
        ~/.bash_history > ~/.zsh_history_migrated

    if [[ -f ~/.zsh_history ]]; then
        echo "Existing .zsh_history found, merging..."
        cat ~/.zsh_history >> ~/.zsh_history_migrated
    fi

    mv ~/.zsh_history_migrated ~/.zsh_history
    echo "Migrated $(wc -l < ~/.zsh_history) history entries"
else
    echo "No .bash_history found, skipping"
fi

echo ""
echo "=== Writing ~/.zshrc ==="
cat > ~/.zshrc << 'ZSHRC'
# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY       # timestamps in history
setopt HIST_IGNORE_ALL_DUPS   # no duplicates
setopt HIST_IGNORE_SPACE      # ignore commands starting with space
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY          # share history across sessions
setopt INC_APPEND_HISTORY     # write immediately, not on exit

# --- Prompt (bash-style: [user@host dir]$ ) ---
PS1='[%n@%m %1~]%# '

# --- Autocorrect [nyae] ---
setopt CORRECT

# --- Completion system ---
autoload -Uz compinit
compinit

zstyle ':completion:*' menu select                    # tab cycles through menu
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # case-insensitive match
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' rehash true                    # pick up new binaries automatically

# --- History search (up/down arrow filters by prefix) ---
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search   # Up
bindkey '^[[B' down-line-or-beginning-search # Down
bindkey '^[OA' up-line-or-beginning-search   # Up (application mode)
bindkey '^[OB' down-line-or-beginning-search # Down (application mode)

# Ctrl+R for incremental history search
bindkey '^R' history-incremental-search-backward

# --- Fish-style inline history suggestions (PSReadLine-like) ---
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
# Right arrow or End to accept, Ctrl+F to accept one word
bindkey '^F' forward-word

# --- Syntax highlighting (load last) ---
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- Misc ---
setopt AUTO_CD          # type a dir name to cd into it
setopt INTERACTIVE_COMMENTS
ZSHRC

echo ""
echo "=== Changing login shell to zsh ==="
chsh -s /usr/bin/zsh
echo "Shell changed for $(whoami)"

echo ""
echo "=== Root setup ==="
echo "Setting up root with the same config..."
sudo cp ~/.zshrc /root/.zshrc

# Migrate root bash history if it exists
sudo bash -c '
if [[ -f /root/.bash_history ]]; then
    ts=$(date +%s)
    awk -v ts="$ts" '\''!seen[$0]++ { printf ": %d:0;%s\n", ts++, $0 }'\'' \
        /root/.bash_history > /root/.zsh_history
    echo "Root history migrated"
fi
'

sudo chsh -s /usr/bin/zsh root
echo "Shell changed for root"

echo ""
echo "=== Done ==="
echo "Log out and back in (or just type 'zsh') to start using it."
echo "Your old .bashrc and .bash_history are untouched."

# Find the command

Find-the-command is a bunch of simple command-not-found hooks, intended for using with pacman, it is primarily targeting Arch-based distros. It can use pacman functionality for searching files, introduced in 5.0 release, but if pkgfile is installed, it will be used since it provides faster search results.

## How does it work?

Interactive shells have an ability to run a specified function when entered command is not found. So these hooks contain a simple function, which is run when shell fails to find any local executables in PATH, aliases and functions matching entered command. There are both interactive hooks, which are providing installation prompt and some other useful functionality (like showing info about package), and 'non-interactive', which are only displaying a package (or list of packages) that provides needed command.

## Installation

	$ git clone https://aur.archlinux.org/find-the-command.git
	$ cd find-the-command
	$ makepkg -si

Alternatively, you can use yay:

	$ yay -S find-the-command

To enable it, you need to source needed file from `/usr/share/doc/find-the-command` directory according to the shell you use. For example, to enable find-the-command zsh hook, you need to place the following in your `~/.zshrc`:

	source /usr/share/doc/find-the-command/ftc.zsh

You can also append some options when sourcing file to customize your experience.

| Option              | Description                                                                     | Bash | Zsh | Fish |
| ------------------- | ------------------------------------------------------------------------------- |:----:|:---:|:----:|
| `askfirst`          | Ask before performing the search.                                               | ✓    | ✓   | ✓    |
| `noprompt`          | Disable installation prompt.                                                    | ✓    | ✓   | ✓    |
| `noupdate`          | Disable asking to update `(database).files` when they are out of date.          | ✓    | ✓   | ✓    |
| `quiet`             | Decrease verbosity.                                                             | ✓    | ✓   | ✓    |
| `su`                | Always use `su -c` instead of `sudo`.                                           | ✓    | ✓   | ✓    |
| `install`           | Automatically install the package without prompting for action.                 | ✓    | ✓   | ✓    |
| `info`              | Automatically print package info without prompting for action.                  | ✓    | ✓   | ✓    |
| `list_files`        | Automatically print a list of package files without prompting for action.       | ✓    | ✓   | ✓    |
| `list_files_paged`  | Automatically print a paged list of package files without prompting for action. | ✓    | ✓   | ✓    |

For example:

	source /usr/share/doc/find-the-command/ftc.zsh quiet su

Searching for commands requires pacman or pkgfile files database. This is detected automatically by the find-the-command functions and will ask you to update when it is necessary. If you wish to run the command manually

	# pacman -Fy
	# pkgfile --update

If the program `fzf` is installed, it will be used to select the packages and show a nice preview of the package and it's files.

There is also systemd timer from package `pacman-contrib` to update pacman files database on weekly basis, so you are less likely to need to update it manually, just run once the following:

	# systemctl enable pacman-filesdb-refresh.timer

Similarly, if using pkgfile you can enable the pkgfile update timer with:

	# systemctl enable pkgfile-update.timer

## Screenshots
![Screenshot](http://i.imgur.com/fFPqn7i.png)
![Screenshot](http://i.imgur.com/A5ahFFO.png)
![Without prompt](http://i.imgur.com/pIHbKEK.png)

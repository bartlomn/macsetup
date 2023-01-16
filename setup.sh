#!/usr/bin/env bash

# 
# DOCK CONFIG
#

# Autohide and magnification for dock
osascript -e "tell application \"System Events\" to set the autohide of the dock preferences to true"
osascript -e "tell application \"System Events\" to set the magnification of the dock preferences to true"

# When you quit an app, the icon will disappear from your Dock
defaults write com.apple.dock static-only -bool true

# Show hidden apps
defaults write com.apple.dock showhidden -bool true

# 
# FINDER CONFIG
#

# Show Library Folder in Finder
chflags nohidden ~/Library

# Show Hidden Files in Finder
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all extensions in Finder
defaults write com.apple.finder AppleShowAllExtensions -bool true

# Show Path Bar in Finder
defaults write com.apple.finder ShowPathbar -bool true

# Show Status Bar in Finder
defaults write com.apple.finder ShowStatusBar -bool true

#!/bin/bash

function update_repo() {
    local git_dir=`find -type d -name '.git'`
    [ -z $git_dir ] && local git_dir=".git"

    if [ -d "$git_dir" ]; then
	local repo=`dirname $git_dir`
        git -C $repo fetch && git -C $repo rebase FETCH_HEAD 
    fi
}


set -gx EDITOR nano

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
if type -q starship
    starship init fish | source
end
set -g fish_greeting ""
if type -q fastfetch
    fastfetch
end
function fish_user_key_bindings 
	bind \cl 'clear; commandline -f repaint'
end

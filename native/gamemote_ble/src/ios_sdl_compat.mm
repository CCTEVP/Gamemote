// Workaround for a Godot 4.7.x iOS template bug (godotengine/godot#122549, fixed for 4.8 by #123903):
// libgodot.a references SDL_IsIPad and SDL_IsAppleTV, which live in SDL's UIKit video
// code that Godot does not compile, so linking an exported iOS app fails with
// "Undefined symbols: _SDL_IsIPad, _SDL_IsAppleTV".
//
// This extension's static library is linked into the same app, so we provide both.
// They are weak: once a Godot version defines them itself, its definitions win and these
// are ignored. Compiled for iOS only.

@import UIKit;

extern "C" {

__attribute__((weak, visibility("default"))) bool SDL_IsIPad(void) {
	return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

__attribute__((weak, visibility("default"))) bool SDL_IsAppleTV(void) {
	return false; // this app only targets iPhone and iPad
}

} // extern "C"

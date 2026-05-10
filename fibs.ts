import { Configurer, Builder } from 'jsr:@floooh/fibs@^1';

export function configure(c: Configurer) {
    c.addImport({
        name: 'chips',
        url: 'https://github.com/floooh/chips',
    });
    c.addImport({
        name: 'dcimgui',
        url: 'https://github.com/floooh/dcimgui',
        files: ['fibs-docking.ts'],
    });
    c.addImport({
        name: 'libs',
        url: 'https://github.com/floooh/fibs-libs',
        files: ['sokol.ts', 'stb.ts'],
    });
    c.addImport({
        name: 'extras',
        url: 'https://github.com/floooh/fibs-extras',
        files: [
            'emscripten.ts',
            'macos.ts',
            'windows.ts',
            'sokolshdc.ts',
            'embedfiles.ts',
            'stdoptions.ts',
            'linux-threads.ts',
            'vscode.ts',
        ],
    });
}

export function build(b: Builder) {
    b.addCmakeVariable('CMAKE_CXX_STANDARD', '20');
    if (b.isMsvc()) {
        b.addCompileOptions([
            '/wd4244',      // conversion from X to Y, possible loss of data
            '/wd4267',      // ditto
            '/wd4324',      // structure was padded due to alignment specifier
            '/wd4200',      // non-standard extension used: zero sized array
            '/wd4201',      // non-standard extension used: nameless struct/union
            '/wd4702',      // unreachable code
        ]);
    } else if (b.isGcc()) {
        b.addCompileOptions([
            '-Wno-stringop-overflow',   // possible false positives
        ]);
    }
    // an interface lib for the chips headers
    b.addTarget('chips', 'interface', (t) => {
        t.setDir(b.importDir('chips'));
        t.addIncludeDirectories(['.']);
    });

    addCommon(b);

    // emulator without UI
    b.addTarget('madNES', 'windowed-exe', (t) => {
        t.setDir('src');
        t.setIdeFolder('src');
        t.addSources([`nes.c`]);
        t.addDependencies(['common']);
    });
    // emulator with UI
    b.addTarget(`madNES-ui`, 'windowed-exe', (t) => {
        t.setDir('src');
        t.setIdeFolder('src');
        t.addSources([`nes.c`, `nes-ui-impl.cc`]);
        t.addCompileDefinitions({ CHIPS_USE_UI: '1' });
        t.addDependencies(['ui']);
    });
}

function addCommon(b: Builder) {
    const dir = 'common';
    const ideFolder = 'common';
    b.addTarget('keybuf', 'lib', (t) => {
        t.setDir(dir);
        t.setIdeFolder(ideFolder);
        t.addSources(['keybuf.c', 'keybuf.h']);
        t.addIncludeDirectories({ dirs: ['.'], scope: 'interface'});
    });
    b.addTarget('common', 'lib', (t) => {
        t.setDir(dir);
        t.setIdeFolder(ideFolder);
        t.addSources([
            'common.h',
            'sokol.c',
            'clock.c', 'clock.h',
            'fs.c', 'fs.h',
            'gfx.c', 'gfx.h',
            'prof.c', 'prof.h',

        ]);
        t.addJob({ job: 'sokolshdc', args: { src: 'shaders.glsl', outDir: t.buildDir() } });
        t.addIncludeDirectories({ dirs: [t.buildDir()], scope: 'private'});
        t.addDependencies(['keybuf', 'sokol', 'chips']);
    });
    b.addTarget('ui', 'lib', (t) => {
        t.setDir(dir);
        t.setIdeFolder(ideFolder);
        t.addSources([ 'ui.cc', 'ui.h' ]);
        t.addDependencies(['imgui-docking', 'common']);
    });
}


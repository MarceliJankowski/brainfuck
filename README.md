# Brainfuck interpreter written in x86-64 AT&T ASM

## Description

As the header says, this is a brainfuck interpreter written in x86-64 AT&T assembly. <br>
It adheres to [this](https://github.com/brain-lang/brainfuck/blob/master/brainfuck.md) specification.

The "**neat**" thing about it, is that it's written without any external libraries (no libc). <br>
Everything's done with good old syscalls!

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
- [Disclaimer](#disclaimer)
- [Motivation](#motivation)
- [Resources](#resources)
- [License](#license)

## Installation

This project uses [GNU make](https://www.gnu.org/software/make) build system, so you're gonna need it. <br>
All build dependencies are listed in [this](./Makefile) Makefile.

Here are installation commands:

```sh
$ git clone https://github.com/MarceliJankowski/brainfuck.git
$ cd ./brainfuck
$ make
```

## Usage

After successful installation, you just need to run `brainfuck` executable with the input source path:

```sh
$ ./brainfuck ./examples/helloWorld.bf
```

**Note**: If you wanna play around, [examples](./examples) directory contains various ready-to-run brainfuck programs.

## Disclaimer

This is my first-ever assembly project (which upon further inspection becomes painfully obvious). <br>
Code isn't of the highest quality, and there are **MANY** things that could be improved upon.

One of which is test coverage. <br>
I didn't bother writing a single test case for this entire thing (_Oops!_). <br>
Suspiciously, I haven't encountered any bugs so far... <br>
This only assures me, that the ones that are hiding are the nasty ones (**beware!**).

The other thing that in a real setting wouldn't fly, is the lack of external dependencies. <br>
While it was great to write my own data structures and utilities for educational value, it's far from recommended. <br>
Modern implementations have hundreds of sophisticated optimizations, there's really no point in competing with them. <br>
Here, it's not that big of a deal, as it's just an educational endeavor. <br>
But in a real project, we wouldn't reinvent the wheel (especially that poorly), we would harness its power!

## Motivation

Ever since [CLA](https://github.com/MarceliJankowski/custom-language-abomination) I've been intrigued with interpreters and compilers.

Now, when I started college I've got plenty of spare time that I can spend on exploring this fascinating topic. <br>
I decided that assembler would be a good starting point (and boy was I right!). <br>
This interpreter taught me a lot and was a great starting point for my upcoming projects.

Speaking of which, I plan to write another interpreter for a made-up language. <br>
Then, once that's done I'll submerge myself in the mesmerizing sea of [Compilers: Principles, Techniques, and Tools](https://en.wikipedia.org/wiki/Compilers:_Principles,_Techniques,_and_Tools). <br>
If it all goes well, I'll emerge victorious, with compiler abomination of my own craftsmanship!

Overall it was a great project for solidifying my assembly knowledge. <br>
I even managed to pass several classes at college with this thing (haha)!

I would definitely recommend building something similar if you're an ASM beginner like me. <br>
Even such simple thing as brainfuck interpreter has a surprising amount of complexity hidden underneath.

## Resources

My whole assembly knowledge (meager as it is) comes from: [Learn to Program with Assembly](https://link.springer.com/book/10.1007/978-1-4842-7437-8) and [Programming from the ground up](https://download-mirror.savannah.gnu.org/releases/pgubook/ProgrammingGroundUp-1-0-booksize.pdf), works written by Jonathan Barlett.

Both of these books are just plain amazing and I can't praise them enough. <br>
They're great resources for anybody wanting to dip their toes in this mysterious assembly world. <br>

Jonathan writes in a very approachable and straightforward way, making it easy to follow along and just learn. <br>
Going through these books was a great deal of pleasure and a solid dose of ASM knowledge. <br>
Each day I eagerly anticipated the moment where I could just sit down, and sink it in.

This project also served as my introduction to [GNU make](https://www.gnu.org/software/make) build system. <br>
I gotta say, that it's an interesting piece of software (although quite convoluted...). <br>

[Managing Projects with GNU Make](http://uploads.mitechie.com/books/Managing_Projects_with_GNU_Make_Third_Edition.pdf) by Robert Mecklenburg helped me wrap my head around this mess. <br>
Another great resource that I can't recommend enough (it would've been hard without it).

I'm really grateful for people like Jonathan Barlett and Robert Mecklenburg. <br>
People that give back to the community, and raise new programmer generations. <br>
I'm hopeful that one day, I'll be able to do the same.

## License

Distributed under the MIT License. <br>
You are free to use, modify, and distribute the source code as long as you include the original copyright notice.

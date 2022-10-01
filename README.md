# canvas-submit-assignment

A simple script to submit your homework from command line.

This only works for [UMICH Canvas](https://umich.instructure.com/).

## Dependencies

`curl`
`jq`

## Usage

Put your token in `~/canvas_token`, or anywhere you like (and modify the code). Pass file paths as arguments. Do not pass a folder.
```shell
canvas-submit-assignment.sh ./a.txt ./b.pdf ./c.java
```
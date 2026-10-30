#!/usr/bin/env node
// Post-process esbuild output to transpile spread operators for Qt V4 engine

const fs = require('fs');

const inputFile = process.argv[2];
if (!inputFile) {
    console.error('Usage: node transpile-spread.js <file>');
    process.exit(1);
}

let code = fs.readFileSync(inputFile, 'utf8');

// 1. Replace spread in array literals: [...expr] -> expr.slice()
// Handle: [...expr], [... expr], [...expr, ...expr2], [a, ...expr, b], etc.
code = code.replace(/\[\s*([^\]]*?\.\.\.[^\]]*?)\s*\]/g, (match, inner) => {
    // Replace each ...expr with expr.slice()
    return '[' + inner.replace(/\.\.\.\s*([a-zA-Z_$][\w$.]*)/g, '$1.slice()') + ']';
});

// 2. Replace spread in function CALLS (not declarations): fn(a, ...args) -> fn.apply(this, [a].concat(args))
// This is complex. For simplicity, handle common cases:
// - fn(...args) -> fn.apply(this, args)
// - fn(a, ...args) -> fn.apply(this, [a].concat(args))
// - obj.method(...args) -> obj.method.apply(obj, args)
// - obj.method(a, ...args) -> obj.method.apply(obj, [a].concat(args))

// First, protect function declarations with rest parameters
// Pattern: function name(...args) { or name(...args) { or const name = (...args) => {
// We'll replace rest parameters in function declarations with a placeholder first
const funcDeclPattern = /(function\s+[a-zA-Z_$][\w$.]*\s*\([^)]*\.\.\.\s*[a-zA-Z_$][\w$.]*\s*\)\s*\{)|([a-zA-Z_$][\w$.]*\s*\([^)]*\.\.\.\s*[a-zA-Z_$][\w$.]*\s*\)\s*\{)|(const\s+[a-zA-Z_$][\w$.]*\s*=\s*\([^)]*\.\.\.\s*[a-zA-Z_$][\w$.]*\s*\)\s*=>)/g;

const protectedDecls = [];
code = code.replace(funcDeclPattern, (match) => {
    const placeholder = `/*FUNC_DECL_${protectedDecls.length}*/`;
    protectedDecls.push(match);
    return placeholder;
});

// Now replace spread in function CALLS only
// First, handle simple case: fn(...args) or obj.method(...args)
// But exclude 'super' which is a keyword
code = code.replace(/([a-zA-Z_$][\w$.]*)\s*\(\s*\.\.\.\s*([a-zA_Z_$][\w$.]*)\s*\)/g, (match, fn, args) => {
    // Skip 'super' keyword
    if (fn === 'super') {
        return match;
    }
    // Skip if this looks like a function declaration (followed by {)
    const after = code.indexOf(match) + match.length;
    const nextChar = code[after]?.trim();
    if (nextChar === '{') {
        // This might be a function declaration, skip
        return match;
    }
    const isMethod = fn.includes('.');
    if (isMethod) {
        const parts = fn.split('.');
        const method = parts.pop();
        const obj = parts.join('.');
        return `${obj}.${method}.apply(${obj}, ${args})`;
    } else {
        return `${fn}.apply(null, ${args})`;
    }
});

// Handle case: fn(a, ...args) or obj.method(a, ...args)
code = code.replace(/([a-zA_Z_$][\w$.]*)\s*\(\s*([^)]*?),\s*\.\.\.\s*([a-zA_Z_$][\w$.]*)\s*\)/g, (match, fn, beforeArgs, spreadArgs) => {
    // Skip if this looks like a function declaration
    const after = code.indexOf(match) + match.length;
    const nextChar = code[after]?.trim();
    if (nextChar === '{') {
        return match;
    }
    const isMethod = fn.includes('.');
    if (isMethod) {
        const parts = fn.split('.');
        const method = parts.pop();
        const obj = parts.join('.');
        return `${obj}.${method}.apply(${obj}, [${beforeArgs}].concat(${spreadArgs}))`;
    } else {
        return `${fn}.apply(null, [${beforeArgs}].concat(${spreadArgs}))`;
    }
});

// 3. Replace super(...arguments) in constructors - but DON'T transpile, as super.apply() doesn't work
// The V4 engine might support super(...arguments) even if it doesn't support other spread
// If it doesn't, we'll need explicit constructors in source
// code = code.replace(/super\s*\(\s*\.\.\.\s*arguments\s*\)/g, (match) => {
//     return '(function(){var _this=this; return Object.getPrototypeOf(_this.constructor.prototype).constructor.apply(_this, arguments);})()';
// });

// 4. Replace push(...items) -> push.apply(arr, items)
// Handle: push(...expr) where expr can be a function call
code = code.replace(/([a-zA_Z_$][\w$.]*)\.push\s*\(\s*\.\.\.\s*([^)]+)\s*\)/g, '$1.push.apply($1, $2)');

// 5. Replace concat(...items) -> concat.apply(arr, items)
code = code.replace(/([a-zA_Z_$][\w$.]*)\.concat\s*\(\s*\.\.\.\s*([^)]+)\s*\)/g, '$1.concat.apply($1, $2)');

// 6. Replace unshift(...items) -> unshift.apply(arr, items)
code = code.replace(/([a-zA_Z_$][\w$.]*)\.unshift\s*\(\s*\.\.\.\s*([^)]+)\s*\)/g, '$1.unshift.apply($1, $2)');

// 7. Replace splice(...items) -> splice.apply(arr, items)
code = code.replace(/([a-zA_Z_$][\w$.]*)\.splice\s*\(\s*\.\.\.\s*([^)]+)\s*\)/g, '$1.splice.apply($1, $2)');

// 7b. Replace generic method calls with spread: obj.method(...args) where method is any name
// This catches console.info("msg", ...args) etc.
code = code.replace(/([a-zA_Z_$][\w$.]*)\s*\(\s*([^)]*?),\s*\.\.\.\s*([a-zA_Z_$][\w$.]*)\s*\)/g, (match, fn, beforeArgs, spreadArgs) => {
    // Skip if already handled (no spread in beforeArgs)
    if (beforeArgs.includes('...')) return match;
    // Skip if this looks like a function declaration
    const after = code.indexOf(match) + match.length;
    const nextChar = code[after]?.trim();
    if (nextChar === '{') return match;
    const isMethod = fn.includes('.');
    if (isMethod) {
        const parts = fn.split('.');
        const method = parts.pop();
        const obj = parts.join('.');
        return `${obj}.${method}.apply(${obj}, [${beforeArgs}].concat(${spreadArgs}))`;
    } else {
        return `${fn}.apply(null, [${beforeArgs}].concat(${spreadArgs}))`;
    }
});

// Restore protected function declarations
protectedDecls.forEach((decl, i) => {
    code = code.replace(`/*FUNC_DECL_${i}*/`, decl);
});

// Write back
fs.writeFileSync(inputFile, code);
console.log('Transpiled spread operators in', inputFile);
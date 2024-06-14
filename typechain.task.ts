import { runTypeChain, glob } from 'typechain'

import fs from "fs";

const typechain_out:string = "typechain-types";

async function main() {
    const cwd = process.cwd()

    // clean typechain-types folder
    if(fs.existsSync(typechain_out))
    {
        fs.rmSync(typechain_out, {recursive:true});
        fs.mkdirSync(typechain_out, {});
    }

    // find all files matching the glob
    const allFiles = glob(cwd, [`out/**/+([a-zA-Z0-9_]).json`])

    const result = await runTypeChain({
        cwd,
        filesToProcess: allFiles,
        allFiles,
        outDir: typechain_out,
        target: 'ethers-v5',
    })
}

main().catch(console.error)


## Installing and running Slither on macOS

1. Install python3-pip3
2. Install solc-select using pip3: `pip3 install --user solc-select`
3. Install slither:  
    
    `pip3 install --user slither-analyzer`
    
4. Add to PATH: `export PATH=$PATH: /Users/somnath/Library/Python/3.10/bin/` 
5. Install solidity version `solc-select install 0.8.16`
6. Select solidity version: `solc-select use 0.8.16`⁠
7. Run slither on the contracts folder with the imports from node-modules:
    
    ```
    slither contracts --solc-args "--base-path . \
        --include-path node_modules/ " --exclude-dependencies --sarif Security/results.sarif

## Known Issues

SSL: CERTIFICATE_VERIFY_FAILED on running solc-select commands [investigation ongoing]

OS X

`pip3 install certifi`
`/Applications/Python\ 3.8/Install\ Certificates.command`

Python distributions on OS X has no certificates and cannot validate SSL connections, a breaking change introduced in Python 3.6. See StackOverflow post for additional details.


Connection refused [investigation ongoing]

`pip3 uninstall solc-select `
`pip3 install solc-select==0.2.0`
`solc-select install `

Try downgrading to solc-select version 0.2.0.

## Viewing the results

1. The first option is to install the vscode extension for slither (trailofbits.slither-vscode). The installation is easy, automatically handles imports. It would show category wise results for the scanned vulnerabilities.
2. The second option is using SARIF () file. Microsoft has a bunch of resources for Sarif file viewing included here https://microsoft.github.io/sarif-web-component/ This includes a frontend to browse the list, and a VSCode plugin as seen below. 
3. Lastly, just running the slither command would output the results on the shell itself.

## Details on detected issues
https://github.com/crytic/slither/wiki/Detector-Documentation

## Future
We will consider using the following additional tools for static and dynamic analysis of contracts
- https://mythx.io/
- https://github.com/ConsenSys/mythril
- https://library.dedaub.com/contracts/hottest



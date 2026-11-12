const express = require('express');
const Docker = require('dockerode');

const app = express();
const docker = new Docker();

app.use(express.static('public'));

async function getContainerStats(containerNameOrId) {
    try {
        const container = docker.getContainer(containerNameOrId);

        // Create an exec instance to run the command inside the container
        const exec = await container.exec({
            Cmd: ['sh', '-c', 'du -sh /usr/share/nginx/html/document_images/'],
            AttachStdout: true,
            AttachStderr: true,
        });

        // Start the exec process
        const execResult = await exec.start();

        // Read the output from the exec process
        const output = await new Promise((resolve, reject) => {
            let result = '';
            execResult.on('data', chunk => (result += chunk.toString()));
            execResult.on('error', reject);
            execResult.on('end', () => resolve(result));
        });

        // Extract only the size information using regular expressions
        const sizeRegex = /(\d+\.\d+|\d+)\s*(\w+)/; // Regular expression to match numbers with units (e.g., 1.5M, 100KB, etc.)
        const match = sizeRegex.exec(output.trim());

        if (match) {
            const size = parseFloat(match[1]);
            const unit = match[2].toLowerCase();
            // Convert to GB if the unit is not GB
            let storageSize = size;
            if (unit === 'k') {
              storageSize = size / 1024 / 1024;
            } else if (unit === 'm') {
              storageSize = size / 1024;
            }

        // Round to two decimal places and add the 'GB' unit
            storageSize = storageSize.toFixed(4) + 'GB';

            return storageSize; // Return the converted storage size in GB
        } else {
            return 'N/A';
        }
    } catch (error) {
        console.error('Error fetching container stats:', error);
        return 'Error fetching container stats';
    }
}

app.get('/container/:nameOrId', async (req, res) => {
    const { nameOrId } = req.params;

    try {
        const storageSize = await getContainerStats(nameOrId);
        res.send({ 'Name': nameOrId, 'StorageStats': { 'Size': storageSize}});
    } catch (error) {
        console.error('Error fetching container stats:', error);
        res.send({'Error': {'Message': 'Error Fetching data'}});
    }
});

const PORT = process.env.PORT || 5050;
app.listen(PORT, () => {
    console.log(`Server running on port�${PORT}`);
});
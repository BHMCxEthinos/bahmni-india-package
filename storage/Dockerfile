# Use the official Node.js 14 image as the base image
FROM node:14

# Set the working directory in the container
# WORKDIR /usr/src/app

# Copy the package.json and package-lock.json files to the container
COPY storage/package*.json .

# Install the Node.js dependencies
RUN npm install

# Copy the rest of the application files to the container
COPY storage/app.js .

# Expose the port that the Node.js application will listen on
EXPOSE 5050

# Start the Node.js application
CMD ["node", "app.js"]
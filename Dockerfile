# Use an official lightweight Python image
FROM python:3.11-slim-bookworm

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt requirements.txt

# Install the Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Expose the port that the app runs on
EXPOSE 5000

# Command to run the application
CMD ["python3", "-m" , "flask", "run", "--host=0.0.0.0"]
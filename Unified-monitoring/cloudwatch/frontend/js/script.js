let currentStep = 1;
const totalSteps = 4;
let selectedResources = [];
let selectedMetrics = [];
let availableMetrics = [];
let selectedKeys = {};
let allResources = []; // stores all fetched resources
let selectedService = null;

const serviceLogos = {
    "EC2": "images/ec2.png",
    "RDS": "images/rds.png",
    "Lambda": "images/lambda.png",
    "DynamoDB": "images/dynamodb.png",
    "ECS": "images/ecs.png",
    "ElastiCache": "images/elasticache.png",
    "ELB": "images/elb.png",
    "SQS": "images/sqs.png",
    "S3": "images/s3.png"
};
document.addEventListener('DOMContentLoaded', async () => {
    try {
        await fetchServices();
        setupEventListeners();
    } catch (error) {
        showError('Failed to initialize application: ' + error.message);
    }
});

function setupEventListeners() {
    // No need for service select change; service card clicks are handled in populateServiceGrid.
    document.getElementById('prevBtn').addEventListener('click', prevStep);
    document.getElementById('nextBtn').addEventListener('click', nextStep);
    document.getElementById('submitBtn').addEventListener('click', submitConfiguration);
    document.getElementById('enableAlerts').addEventListener('change', handleAlertsToggle);
    document.querySelector('.close').addEventListener('click', closeModal);
    document.getElementById('regionFilter').addEventListener('change', filterAndDisplayResources);
}

async function fetchServices() {
    const response = await fetch('/cloudwatch/api/services');
    if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
    }
    const services = await response.json();
    populateServiceGrid(services);
}

function populateServiceGrid(services) {
    const serviceGrid = document.getElementById('serviceGrid');
    serviceGrid.innerHTML = '';
    services.forEach(service => {
        const card = document.createElement('div');
        card.className = 'service-card';
        card.innerHTML = `
            <img src="${serviceLogos[service] || 'images/default.png'}" alt="${service}" class="service-icon">
            <h3>${service}</h3>
            <p>Click to select ${service}</p>
        `;
        card.addEventListener('click', () => {
            // Deselect any previously selected card
            const cards = document.querySelectorAll('.service-card');
            cards.forEach(c => c.classList.remove('selected'));
            // Mark this card as selected and store the service name
            card.classList.add('selected');
            selectedService = service;
            // Automatically move to the next step
            nextStep();
        });
        serviceGrid.appendChild(card);
    });
}


async function handleServiceChange() {
    const service = document.getElementById('service').value;
    if (!service) return;
    try {
        const response = await fetch(`/cloudwatch/api/metrics/${service}`);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        availableMetrics = await response.json();
        updateMetricsGrid();
    } catch (error) {
        showError('Failed to fetch metrics: ' + error.message);
    }
}

function updateMetricsGrid() {
    const metricsGrid = document.getElementById('metricsGrid');
    metricsGrid.innerHTML = '';
    
    availableMetrics.forEach(metric => {
        const div = document.createElement('div');
        div.className = 'metric-item';
        div.innerHTML = `
            <input type="checkbox" id="${metric.name}" name="metrics" value="${metric.name}"
                   ${selectedMetrics.some(m => m.name === metric.name) ? 'checked' : ''}>
            <label for="${metric.name}">${metric.name}</label>
        `;
        div.querySelector('input').addEventListener('change', (e) => handleMetricSelection(e, metric));
        metricsGrid.appendChild(div);
    });
}

function handleMetricSelection(event, metric) {
    if (event.target.checked) {
        selectedMetrics.push({
            name: metric.name,
            namespace: metric.namespace
        });
    } else {
        selectedMetrics = selectedMetrics.filter(m => m.name !== metric.name);
    }
    updateNavigationButtons();
}

function nextStep() {
    if (validateCurrentStep()) {
        if (currentStep === 1) {
            if (!selectedService) {
                showError('Please select an AWS service.');
                return;
            }
            // Fetch resources for the chosen service
            fetch(`/cloudwatch/api/resources/${selectedService}`)
                .then(response => {
                    if (!response.ok) {
                        throw new Error('Failed to fetch resources');
                    }
                    return response.json();
                })
                .then(resources => {
                    updateResourceList(resources);
                    document.getElementById(`step${currentStep}`).style.display = 'none';
                    currentStep++;
                    document.getElementById(`step${currentStep}`).style.display = 'block';
                    updateNavigationButtons();
                })
                .catch(error => showError(error.message));
        } else if (currentStep === 2) {
            // Before moving to step 3, fetch the metrics for the selected service
            fetch(`/cloudwatch/api/metrics/${selectedService}`)
                .then(response => {
                    if (!response.ok) {
                        throw new Error('Failed to fetch metrics');
                    }
                    return response.json();
                })
                .then(metrics => {
                    availableMetrics = metrics;
                    updateMetricsGrid();
                    document.getElementById(`step${currentStep}`).style.display = 'none';
                    currentStep++;
                    document.getElementById(`step${currentStep}`).style.display = 'block';
                    updateNavigationButtons();
                })
                .catch(error => showError(error.message));
        } else {
            document.getElementById(`step${currentStep}`).style.display = 'none';
            currentStep++;
            document.getElementById(`step${currentStep}`).style.display = 'block';
            updateNavigationButtons();
        }
    }
}

function updateResourceList(resources) {
    // Save full list of resources.
    allResources = resources;
    // Populate the region filter dropdown using unique region values.
    populateRegionFilter();
    // Initially display all resources.
    filterAndDisplayResources();
}

function populateRegionFilter() {
    const regionFilter = document.getElementById('regionFilter');
    regionFilter.innerHTML = `<option value="">All Regions</option>`;
    const regions = Array.from(new Set(allResources.map(r => r.Region))).sort();
    regions.forEach(region => {
        const option = document.createElement('option');
        option.value = region;
        option.textContent = region;
        regionFilter.appendChild(option);
    });
}

function filterAndDisplayResources() {
    const regionFilter = document.getElementById('regionFilter');
    const selectedRegion = regionFilter.value;
    let filteredResources = allResources;
    if (selectedRegion) {
        filteredResources = allResources.filter(r => r.Region === selectedRegion);
    }
    updateResourceListUI(filteredResources);
}

function updateResourceListUI(resources) {
    const resourceList = document.getElementById('resourceList');
    resourceList.innerHTML = '';
    
    resources.forEach(resource => {
        // Only show key upload if the selected service is EC2
        const keyUploadHTML = (selectedService === "EC2") 
            ? `<input type="file" id="key-${resource.Id}" class="key-upload" style="display:none;" accept=".pem">` 
            : '';
        const div = document.createElement('div');
        div.className = 'resource-item';
        div.innerHTML = `
            <input type="checkbox" id="${resource.Id}" value="${resource.Id}"
                   ${selectedResources.find(r => r.Id === resource.Id) ? 'checked' : ''}>
            <label for="${resource.Id}">
                ${resource.Name} <small>(${resource.Region})</small>
                <span class="resource-info">${resource.Id} - ${resource.Type}</span>
                <span class="resource-ips">
                    Public: ${resource.PublicIpAddress ? resource.PublicIpAddress : 'N/A'} | 
                    Private: ${resource.PrivateIpAddress ? resource.PrivateIpAddress : 'N/A'}
                </span>
            </label>
            ${keyUploadHTML}
        `;
        // When a resource checkbox is changed, update the selection and navigation buttons
        div.querySelector('input[type="checkbox"]').addEventListener('change', (e) => handleResourceSelection(e, resource));
        
        // Only add file upload event if service is EC2
        if (selectedService === "EC2" && keyUploadHTML !== '') {
            div.querySelector('.key-upload').addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (file) {
                    selectedKeys[resource.Id] = file;
                } else {
                    delete selectedKeys[resource.Id];
                }
            });
        }
        resourceList.appendChild(div);
    });
}

function handleResourceSelection(event, resource) {
    const keyInput = document.getElementById(`key-${resource.Id}`);
    if (event.target.checked) {
        if (!selectedResources.find(r => r.Id === resource.Id)) {
            selectedResources.push(resource);
        }
        keyInput.style.display = 'inline-block';
    } else {
        selectedResources = selectedResources.filter(r => r.Id !== resource.Id);
        keyInput.style.display = 'none';
        keyInput.value = "";
        delete selectedKeys[resource.Id];
    }
    updateNavigationButtons();
}

function handleAlertsToggle(event) {
    const thresholdsDiv = document.getElementById('thresholds');
    thresholdsDiv.style.display = event.target.checked ? 'block' : 'none';
    
    if (event.target.checked) {
        updateThresholdsDisplay();
    }
}

function updateThresholdsDisplay() {
    const thresholdsDiv = document.getElementById('thresholds');
    thresholdsDiv.innerHTML = '';
    
    selectedMetrics.forEach(metric => {
        const container = document.createElement('div');
        container.className = 'metric-threshold-container';
        container.innerHTML = `
            <h4 class="metric-name">${metric.name}</h4>
            <div class="slider-container warning">
                <label for="${metric.name}-warning">Warning Threshold (%)</label>
                <input type="range" id="${metric.name}-warning" 
                       min="0" max="100" value="70" 
                       class="threshold-slider warning-slider">
                <span class="threshold-value warning-value">70%</span>
            </div>
            <div class="slider-container critical">
                <label for="${metric.name}-critical">Critical Threshold (%)</label>
                <input type="range" id="${metric.name}-critical" 
                       min="0" max="100" value="90" 
                       class="threshold-slider critical-slider">
                <span class="threshold-value critical-value">90%</span>
            </div>
        `;
        
        const warningSlider = container.querySelector('.warning-slider');
        const criticalSlider = container.querySelector('.critical-slider');
        const warningValue = container.querySelector('.warning-value');
        const criticalValue = container.querySelector('.critical-value');
        
        warningSlider.addEventListener('input', () => {
            const warning = parseInt(warningSlider.value);
            const critical = parseInt(criticalSlider.value);
            if (warning >= critical) {
                warningSlider.value = critical - 1;
                warningValue.textContent = `${critical - 1}%`;
            } else {
                warningValue.textContent = `${warning}%`;
            }
        });
        
        criticalSlider.addEventListener('input', () => {
            const warning = parseInt(warningSlider.value);
            const critical = parseInt(criticalSlider.value);
            if (critical <= warning) {
                criticalSlider.value = warning + 1;
                criticalValue.textContent = `${warning + 1}%`;
            } else {
                criticalValue.textContent = `${critical}%`;
            }
        });
        
        thresholdsDiv.appendChild(container);
    });
}

function prevStep() {
    document.getElementById(`step${currentStep}`).style.display = 'none';
    currentStep--;
    document.getElementById(`step${currentStep}`).style.display = 'block';
    updateNavigationButtons();
}

function updateNavigationButtons() {
    document.getElementById('prevBtn').style.display = currentStep > 1 ? 'block' : 'none';
    document.getElementById('nextBtn').style.display = currentStep < totalSteps ? 'block' : 'none';
    document.getElementById('submitBtn').style.display = currentStep === totalSteps ? 'block' : 'none';
}

function validateCurrentStep() {
    switch (currentStep) {
        case 1:
            return selectedService !== null;
        case 2:
            return selectedResources.length > 0;
        case 3:
            return selectedMetrics.length > 0;
        default:
            return true;
    }
}

async function submitConfiguration() {
    // Show progress bar and initialize progress value to 0
    const progressContainer = document.getElementById('progressContainer');
    const progressBar = document.getElementById('progressBar');
    progressContainer.style.display = 'block';
    progressBar.style.width = '0%';

    let progress = 0;
    // Simulate progress increment (e.g., every second increase by 5% up to 95%)
    const progressInterval = setInterval(() => {
        if (progress < 95) {
            progress += 5;
            progressBar.style.width = progress + '%';
        }
    }, 1000);

    const config = {
        service: selectedService,
        region: selectedResources.length > 0 ? selectedResources[0].Region : '',
        resources: selectedResources,
        metrics: selectedMetrics,
        alerts: document.getElementById('enableAlerts').checked,
        thresholds: {},
        keys: {}
    };

    if (config.alerts) {
        selectedMetrics.forEach(metric => {
            config.thresholds[metric.name] = {
                warning: document.getElementById(`${metric.name}-warning`).value,
                critical: document.getElementById(`${metric.name}-critical`).value
            };
        });
    }

    const formData = new FormData();
    formData.append('config', JSON.stringify(config));

    selectedResources.forEach(resource => {
        if (selectedKeys[resource.Id]) {
            formData.append(`key_${resource.Id}`, selectedKeys[resource.Id]);
        }
    });

    try {
        const response = await fetch('/cloudwatch/api/configure', {
            method: 'POST',
            body: formData
        });
        // Clear the simulated progress timer
        clearInterval(progressInterval);
        // Set progress to 100%
        progress = 100;
        progressBar.style.width = '100%';
        const contentType = response.headers.get("content-type");
        if (contentType && contentType.indexOf("application/json") !== -1) {
            const result = await response.json();
            // Optionally, wait a bit before hiding the progress bar
            setTimeout(() => {
                progressContainer.style.display = 'none';
                showSuccess(result);
            }, 500);
        } else {
            const text = await response.text();
            throw new Error("Non-JSON response received: " + text.substring(0, 100));
        }
    } catch (error) {
        clearInterval(progressInterval);
        progressContainer.style.display = 'none';
        showError("Failed to configure monitoring: " + error.message);
    }
}

function showError(message) {
    const modal = document.getElementById('resultModal');
    const content = document.getElementById('modalContent');
    content.innerHTML = `<div class="error-message">${message}</div>`;
    modal.style.display = 'block';
}

function showSuccess(result) {
    const modal = document.getElementById('resultModal');
    const content = document.getElementById('modalContent');
    content.innerHTML = `
        <div class="success-message">
            <h3>Monitoring configuration completed successfully!</h3>
            <p><strong>Dashboard Name:</strong> ${result.dashboardName}</p>
            <p><strong>SNS Topic ARN:</strong> ${result.snsTopicArn}</p>
            <p><strong>Important:</strong> Please add subscribers to the SNS topic "${result.topicName}" to receive alerts.</p>
            <div class="dashboard-link">
                <a href="${result.dashboardUrl}" target="_blank" class="btn">View Dashboard</a>
            </div>
        </div>
    `;
    modal.style.display = 'block';
}

function closeModal() {
    document.getElementById('resultModal').style.display = 'none';
}

window.onclick = function(event) {
    const modal = document.getElementById('resultModal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
};
process MONITOR_SYSTEM_RESOURCES {
    tag "system_monitoring"
    label 'process_single'
    publishDir "${params.outdir}/resource_monitoring", mode: 'copy'

    input:
    val system_config

    output:
    path "system_metrics.json", emit: system_metrics
    path "resource_limits.json", emit: resource_limits
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    
    """
    #!/usr/bin/env python3

    import json
    import os
    import time
    import platform
    import subprocess
    import psutil
    from pathlib import Path
    from datetime import datetime

    system_config = json.loads('${new groovy.json.JsonBuilder(system_config).toString()}')
    
    def get_cpu_info():
        'Get detailed CPU information'
        cpu_info = {
            'physical_cores': psutil.cpu_count(logical=False),
            'logical_cores': psutil.cpu_count(logical=True),
            'current_freq_mhz': 0,
            'max_freq_mhz': 0,
            'architecture': platform.machine(),
            'cpu_brand': 'unknown'
        }
        
        try:
            # Get CPU frequency information
            freq_info = psutil.cpu_freq()
            if freq_info:
                cpu_info['current_freq_mhz'] = round(freq_info.current, 0)
                cpu_info['max_freq_mhz'] = round(freq_info.max, 0)
            
            # Get CPU brand information (platform specific)
            if platform.system() == "Darwin":  # macOS
                try:
                    result = subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], 
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        cpu_info['cpu_brand'] = result.stdout.strip()
                except:
                    pass
            elif platform.system() == "Linux":
                try:
                    with open('/proc/cpuinfo', 'r') as f:
                        for line in f:
                            if 'model name' in line:
                                cpu_info['cpu_brand'] = line.split(':')[1].strip()
                                break
                except:
                    pass
        
        except Exception as e:
            print(f"Warning: Could not get complete CPU info: {e}")
        
        return cpu_info
    
    def get_memory_info():
        'Get detailed memory information'
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        memory_info = {
            'total_gb': round(memory.total / (1024**3), 2),
            'available_gb': round(memory.available / (1024**3), 2),
            'used_gb': round(memory.used / (1024**3), 2),
            'free_gb': round(memory.free / (1024**3), 2),
            'utilization_percent': memory.percent,
            'swap_total_gb': round(swap.total / (1024**3), 2),
            'swap_used_gb': round(swap.used / (1024**3), 2),
            'swap_utilization_percent': swap.percent
        }
        
        return memory_info
    
    def get_gpu_info():
        'Get GPU information'
        gpu_info = {
            'nvidia_gpus': [],
            'apple_gpus': [],
            'total_gpu_memory_gb': 0,
            'gpu_available': False
        }
        
        try:
            # Check for NVIDIA GPUs
            if os.system('which nvidia-smi > /dev/null 2>&1') == 0:
                try:
                    result = subprocess.run([
                        'nvidia-smi', '--query-gpu=name,memory.total,memory.used,utilization.gpu',
                        '--format=csv,noheader,nounits'
                    ], capture_output=True, text=True)
                    
                    if result.returncode == 0:
                        for line in result.stdout.strip().split('\\n'):
                            if line.strip():
                                parts = [p.strip() for p in line.split(',')]
                                if len(parts) >= 4:
                                    gpu_info['nvidia_gpus'].append({
                                        'name': parts[0],
                                        'memory_total_mb': int(parts[1]),
                                        'memory_used_mb': int(parts[2]),
                                        'utilization_percent': int(parts[3])
                                    })
                except Exception as e:
                    print(f"Warning: Could not get NVIDIA GPU info: {e}")
            
            # Check for Apple Silicon GPUs (macOS)
            if platform.system() == "Darwin" and platform.machine() == "arm64":
                try:
                    result = subprocess.run(['system_profiler', 'SPDisplaysDataType'], 
                                          capture_output=True, text=True)
                    if result.returncode == 0 and 'Apple' in result.stdout:
                        gpu_info['apple_gpus'].append({
                            'name': 'Apple Silicon Integrated GPU',
                            'memory_shared': True,
                            'metal_support': True
                        })
                except Exception as e:
                    print(f"Warning: Could not get Apple GPU info: {e}")
            
            # Calculate total GPU memory
            gpu_info['total_gpu_memory_gb'] = sum(
                gpu['memory_total_mb'] / 1024 for gpu in gpu_info['nvidia_gpus']
            )
            
            gpu_info['gpu_available'] = len(gpu_info['nvidia_gpus']) > 0 or len(gpu_info['apple_gpus']) > 0
            
        except Exception as e:
            print(f"Warning: Could not get GPU information: {e}")
        
        return gpu_info
    
    def get_disk_info():
        'Get disk usage information'
        disk_info = {
            'total_gb': 0,
            'used_gb': 0,
            'free_gb': 0,
            'utilization_percent': 0,
            'io_busy_percent': 0
        }
        
        try:
            # Get disk usage for current directory
            usage = psutil.disk_usage('.')
            disk_info['total_gb'] = round(usage.total / (1024**3), 2)
            disk_info['used_gb'] = round(usage.used / (1024**3), 2)
            disk_info['free_gb'] = round(usage.free / (1024**3), 2)
            disk_info['utilization_percent'] = round((usage.used / usage.total) * 100, 1)
            
            # Get disk I/O statistics if available
            try:
                io_stats = psutil.disk_io_counters()
                if io_stats:
                    # This is a simplified I/O busy calculation
                    # In reality, you'd need to sample over time
                    disk_info['io_read_mb'] = round(io_stats.read_bytes / (1024**2), 2)
                    disk_info['io_write_mb'] = round(io_stats.write_bytes / (1024**2), 2)
            except:
                pass
                
        except Exception as e:
            print(f"Warning: Could not get disk information: {e}")
        
        return disk_info
    
    def get_network_info():
        'Get network information'
        network_info = {
            'interfaces': [],
            'total_bytes_sent': 0,
            'total_bytes_recv': 0
        }
        
        try:
            network_stats = psutil.net_io_counters(pernic=True)
            for interface, stats in network_stats.items():
                if not interface.startswith('lo'):  # Skip loopback
                    network_info['interfaces'].append({
                        'name': interface,
                        'bytes_sent': stats.bytes_sent,
                        'bytes_recv': stats.bytes_recv,
                        'packets_sent': stats.packets_sent,
                        'packets_recv': stats.packets_recv
                    })
                    network_info['total_bytes_sent'] += stats.bytes_sent
                    network_info['total_bytes_recv'] += stats.bytes_recv
        
        except Exception as e:
            print(f"Warning: Could not get network information: {e}")
        
        return network_info
    
    def get_current_load():
        'Get current system load metrics'
        load_info = {
            'cpu_utilization_percent': 0,
            'memory_utilization_percent': 0,
            'load_average_1min': 0,
            'load_average_5min': 0,
            'load_average_15min': 0,
            'active_processes': 0,
            'load_classification': 'unknown'
        }
        
        try:
            # CPU utilization (average over 1 second)
            load_info['cpu_utilization_percent'] = psutil.cpu_percent(interval=1)
            
            # Memory utilization
            memory = psutil.virtual_memory()
            load_info['memory_utilization_percent'] = memory.percent
            
            # Load averages (Unix-like systems)
            if hasattr(os, 'getloadavg'):
                load_avg = os.getloadavg()
                load_info['load_average_1min'] = round(load_avg[0], 2)
                load_info['load_average_5min'] = round(load_avg[1], 2)
                load_info['load_average_15min'] = round(load_avg[2], 2)
            
            # Process count
            load_info['active_processes'] = len(psutil.pids())
            
            # Load classification
            cpu_util = load_info['cpu_utilization_percent']
            mem_util = load_info['memory_utilization_percent']
            
            if cpu_util > 80 or mem_util > 85:
                load_info['load_classification'] = 'high'
            elif cpu_util > 60 or mem_util > 70:
                load_info['load_classification'] = 'medium'
            else:
                load_info['load_classification'] = 'low'
        
        except Exception as e:
            print(f"Warning: Could not get load information: {e}")
        
        return load_info
    
    def calculate_resource_limits():
        'Calculate recommended resource limits based on system capacity'
        cpu_info = get_cpu_info()
        memory_info = get_memory_info()
        gpu_info = get_gpu_info()
        current_load = get_current_load()
        
        # Conservative resource allocation to leave headroom
        safety_factor = 0.8  # Use 80% of available resources
        
        limits = {
            'max_cpu_cores': max(1, int(cpu_info['logical_cores'] * safety_factor)),
            'max_memory_gb': max(1, memory_info['available_gb'] * safety_factor),
            'max_gpu_memory_gb': gpu_info['total_gpu_memory_gb'] * safety_factor,
            'recommended_parallel_jobs': max(1, min(4, cpu_info['physical_cores'] // 2)),
            'disk_space_warning_gb': 10,  # Warn when less than 10GB free
            'memory_pressure_threshold': 85,  # Memory utilization %
            'cpu_pressure_threshold': 80,   # CPU utilization %
            'current_capacity': {
                'cpu_available_cores': max(1, int(cpu_info['logical_cores'] * (1 - current_load['cpu_utilization_percent']/100))),
                'memory_available_gb': memory_info['available_gb'],
                'can_handle_large_jobs': memory_info['available_gb'] > 16 and current_load['load_classification'] in ['low', 'medium'],
                'recommended_batch_size': 10 if current_load['load_classification'] == 'low' else 5
            }
        }
        
        return limits
    
    # Collect all system information
    print("Monitoring system resources...")
    
    system_metrics = {
        'timestamp': datetime.now().isoformat(),
        'hostname': platform.node(),
        'platform': platform.system(),
        'platform_version': platform.release(),
        'architecture': platform.machine(),
        'cpu': get_cpu_info(),
        'memory': get_memory_info(),
        'gpu': get_gpu_info(),
        'disk': get_disk_info(),
        'network': get_network_info(),
        'current_load': get_current_load(),
        'monitoring_config': system_config
    }
    
    resource_limits = calculate_resource_limits()
    
    # Save system metrics
    with open('system_metrics.json', 'w') as f:
        json.dump(system_metrics, f, indent=2)
    
    # Save resource limits
    with open('resource_limits.json', 'w') as f:
        json.dump(resource_limits, f, indent=2)
    
    print("System monitoring complete:")
    print(f"  CPU: {system_metrics['cpu']['logical_cores']} cores, {system_metrics['current_load']['cpu_utilization_percent']:.1f}% utilization")
    print(f"  Memory: {system_metrics['memory']['available_gb']:.1f}GB available of {system_metrics['memory']['total_gb']:.1f}GB total")
    print(f"  GPU: {'Available' if system_metrics['gpu']['gpu_available'] else 'Not available'}")
    print(f"  Load: {system_metrics['current_load']['load_classification']}")
    print(f"  Max recommended CPU cores: {resource_limits['max_cpu_cores']}")
    print(f"  Max recommended memory: {resource_limits['max_memory_gb']:.1f}GB")
    print(f"  Recommended parallel jobs: {resource_limits['recommended_parallel_jobs']}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''"${task.process}":
    python: "3.9"
    psutil: "5.9.0"
    resource_monitoring: "1.0"''')
    """

    stub:
    """
    cat > system_metrics.json <<'STUB_EOF'
{
  "timestamp": "2024-01-01T00:00:00",
  "hostname": "stub-hostname",
  "platform": "Linux",
  "platform_version": "5.15.0",
  "architecture": "x86_64",
  "cpu": {
    "physical_cores": 4,
    "logical_cores": 8,
    "current_freq_mhz": 2400.0,
    "max_freq_mhz": 3200.0,
    "architecture": "x86_64",
    "cpu_brand": "Intel Core i7"
  },
  "memory": {
    "total_gb": 16.0,
    "available_gb": 12.0,
    "used_gb": 4.0,
    "free_gb": 12.0,
    "utilization_percent": 25.0,
    "swap_total_gb": 8.0,
    "swap_used_gb": 0.0,
    "swap_utilization_percent": 0.0
  },
  "gpu": {
    "nvidia_gpus": [],
    "apple_gpus": [],
    "total_gpu_memory_gb": 0.0,
    "gpu_available": false
  },
  "disk": {
    "total_gb": 500.0,
    "used_gb": 300.0,
    "free_gb": 200.0,
    "utilization_percent": 60.0,
    "io_busy_percent": 5.0
  },
  "network": {
    "interfaces": [],
    "total_bytes_sent": 0,
    "total_bytes_recv": 0
  },
  "current_load": {
    "cpu_utilization_percent": 20.0,
    "memory_utilization_percent": 25.0,
    "load_average_1min": 1.5,
    "load_average_5min": 1.2,
    "load_average_15min": 1.0,
    "active_processes": 150,
    "load_classification": "low"
  },
  "monitoring_config": {}
}
STUB_EOF

    cat > resource_limits.json <<'STUB_EOF'
{
  "max_cpu_cores": 6,
  "max_memory_gb": 12.0,
  "max_gpu_memory_gb": 0.0,
  "recommended_parallel_jobs": 2,
  "disk_space_warning_gb": 10,
  "memory_pressure_threshold": 85,
  "cpu_pressure_threshold": 80,
  "current_capacity": {
    "cpu_available_cores": 6,
    "memory_available_gb": 12.0,
    "can_handle_large_jobs": false,
    "recommended_batch_size": 10
  }
}
STUB_EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        psutil: "5.9.0"
        resource_monitoring: "1.0"
    END_VERSIONS
    """
}
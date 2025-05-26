import React, { useState, useRef } from 'react';
import { Upload, Download, RefreshCw, CheckCircle, XCircle, File, Image, Zap, Globe, Shield, Smartphone } from 'lucide-react';

const FileConverter = () => {
    const [file, setFile] = useState(null);
    const [targetFormat, setTargetFormat] = useState('');
    const [isUploading, setIsUploading] = useState(false);
    const [isConverting, setIsConverting] = useState(false);
    const [conversionResult, setConversionResult] = useState(null);
    const [error, setError] = useState('');
    const [userSession] = useState(() => Math.random().toString(36).substring(2, 15));
    const fileInputRef = useRef(null);

    //API Gateway URL from Terraform output
    const API_BASE_URL = 'https://your-api-id.execute-api.region.amazonaws.com/prod';

    const imageFormats = [
        { value: 'jpg', label: 'JPEG (.jpg)' },
        { value: 'png', label: 'PNG (.png)' },
        { value: 'gif', label: 'GIF (.gif)' },
        { value: 'bmp', label: 'BMP (.bmp)' },
        { value: 'tiff', label: 'TIFF (.tiff)' },
        { value: 'webp', label: 'WebP (.webp)' }
    ];

    const handleFileSelect = (event) => {
        const selectedFile = event.target.files[0];
        if (selectedFile) {
            setFile(selectedFile);
            setError('');
            setConversionResult(null);

            // Auto-select target format based on file type
            const fileExt = selectedFile.name.split('.').pop().toLowerCase();
            if (isImageFile(fileExt)) {
                const suggestedFormat = fileExt === 'jpg' ? 'png' : 'jpg';
                setTargetFormat(suggestedFormat);
            }
        }
    };

    const handleDrop = (event) => {
        event.preventDefault();
        const droppedFile = event.dataTransfer.files[0];
        if (droppedFile) {
            setFile(droppedFile);
            setError('');
            setConversionResult(null);

            const fileExt = droppedFile.name.split('.').pop().toLowerCase();
            if (isImageFile(fileExt)) {
                const suggestedFormat = fileExt === 'jpg' ? 'png' : 'jpg';
                setTargetFormat(suggestedFormat);
            }
        }
    };

    const handleDragOver = (event) => {
        event.preventDefault();
    };

    const isImageFile = (extension) => {
        return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'webp'].includes(extension.toLowerCase());
    };

    const convertFileToBase64 = (file) => {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.readAsDataURL(file);
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = error => reject(error);
        });
    };

    const uploadFile = async () => {
        if (!file || !targetFormat) {
            setError('Please select a file and target format');
            return null;
        }

        setIsUploading(true);
        setError('');

        try {
            const base64Data = await convertFileToBase64(file);

            const response = await fetch(`${API_BASE_URL}/upload`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    file_data: base64Data,
                    file_name: file.name,
                    content_type: file.type,
                    user_session: userSession
                })
            });

            if (!response.ok) {
                throw new Error('Upload failed');
            }

            const result = await response.json();
            return result.conversion_id;
        } catch (err) {
            setError('Failed to upload file: ' + err.message);
            return null;
        } finally {
            setIsUploading(false);
        }
    };

    const convertFile = async (conversionId) => {
        setIsConverting(true);

        try {
            const response = await fetch(`${API_BASE_URL}/convert`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    conversion_id: conversionId,
                    target_format: targetFormat
                })
            });

            if (!response.ok) {
                throw new Error('Conversion failed');
            }

            const result = await response.json();
            setConversionResult(result);
        } catch (err) {
            setError('Failed to convert file: ' + err.message);
        } finally {
            setIsConverting(false);
        }
    };

    const handleConvert = async () => {
        const conversionId = await uploadFile();
        if (conversionId) {
            await convertFile(conversionId);
        }
    };

    const resetForm = () => {
        setFile(null);
        setTargetFormat('');
        setConversionResult(null);
        setError('');
        if (fileInputRef.current) {
            fileInputRef.current.value = '';
        }
    };

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-900">
            {/* Hero Section */}
            <div className="relative overflow-hidden">
                <div className="absolute inset-0 bg-black opacity-20"></div>
                <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24">
                    <div className="text-center">
                        <div className="flex justify-center mb-8">
                            <div className="relative">
                                <div className="absolute inset-0 bg-gradient-to-r from-cyan-400 to-purple-500 rounded-full blur-xl opacity-75 animate-pulse"></div>
                                <div className="relative bg-white bg-opacity-10 backdrop-blur-lg rounded-full p-6 border border-white border-opacity-20">
                                    <Zap className="h-12 w-12 text-white" />
                                </div>
                            </div>
                        </div>
                        <h1 className="text-5xl md:text-7xl font-bold text-white mb-6 bg-clip-text text-transparent bg-gradient-to-r from-cyan-400 via-purple-400 to-pink-400">
                            File Converter Pro
                        </h1>
                        <p className="text-xl md:text-2xl text-purple-100 mb-8 max-w-3xl mx-auto leading-relaxed">
                            Transform your files instantly with our lightning-fast, secure, and serverless conversion platform
                        </p>

                        {/* Feature Pills */}
                        <div className="flex flex-wrap justify-center gap-4 mb-12">
                            <div className="flex items-center bg-white bg-opacity-10 backdrop-blur-lg rounded-full px-6 py-3 border border-white border-opacity-20">
                                <Globe className="h-5 w-5 text-cyan-400 mr-2" />
                                <span className="text-white font-medium">Global CDN</span>
                            </div>
                            <div className="flex items-center bg-white bg-opacity-10 backdrop-blur-lg rounded-full px-6 py-3 border border-white border-opacity-20">
                                <Shield className="h-5 w-5 text-green-400 mr-2" />
                                <span className="text-white font-medium">Secure Processing</span>
                            </div>
                            <div className="flex items-center bg-white bg-opacity-10 backdrop-blur-lg rounded-full px-6 py-3 border border-white border-opacity-20">
                                <Smartphone className="h-5 w-5 text-purple-400 mr-2" />
                                <span className="text-white font-medium">Mobile Friendly</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Main Conversion Interface */}
            <div className="relative max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 pb-24 -mt-12">
                <div className="bg-white bg-opacity-10 backdrop-blur-2xl rounded-3xl border border-white border-opacity-20 shadow-2xl overflow-hidden">
                    <div className="p-8 md:p-12">
                        {/* File Upload Area */}
                        <div className="mb-8">
                            <label className="block text-white text-lg font-semibold mb-4">
                                Choose Your File
                            </label>
                            <div
                                className="relative border-2 border-dashed border-purple-300 border-opacity-50 rounded-2xl p-12 text-center hover:border-purple-400 hover:border-opacity-70 transition-all duration-300 cursor-pointer group"
                                onDrop={handleDrop}
                                onDragOver={handleDragOver}
                                onClick={() => fileInputRef.current?.click()}
                            >
                                <input
                                    ref={fileInputRef}
                                    type="file"
                                    onChange={handleFileSelect}
                                    className="hidden"
                                    accept="image/*"
                                />

                                <div className="flex flex-col items-center">
                                    <div className="relative mb-6">
                                        <div className="absolute inset-0 bg-gradient-to-r from-cyan-400 to-purple-500 rounded-full blur-lg opacity-50 group-hover:opacity-75 transition-opacity"></div>
                                        <div className="relative bg-white bg-opacity-10 backdrop-blur-lg rounded-full p-6 border border-white border-opacity-20">
                                            {file ? (
                                                <Image className="h-12 w-12 text-green-400" />
                                            ) : (
                                                <Upload className="h-12 w-12 text-purple-300 group-hover:text-purple-200 transition-colors" />
                                            )}
                                        </div>
                                    </div>

                                    {file ? (
                                        <div className="text-center">
                                            <p className="text-white text-xl font-semibold mb-2">{file.name}</p>
                                            <p className="text-purple-200">
                                                {(file.size / 1024 / 1024).toFixed(2)} MB
                                            </p>
                                        </div>
                                    ) : (
                                        <div className="text-center">
                                            <p className="text-white text-xl font-semibold mb-2">
                                                Drop your file here or click to browse
                                            </p>
                                            <p className="text-purple-200">
                                                Supports: JPG, PNG, GIF, BMP, TIFF, WebP
                                            </p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>

                        {/* Format Selection */}
                        {file && isImageFile(file.name.split('.').pop()) && (
                            <div className="mb-8">
                                <label className="block text-white text-lg font-semibold mb-4">
                                    Convert To
                                </label>
                                <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                                    {imageFormats.map((format) => (
                                        <button
                                            key={format.value}
                                            onClick={() => setTargetFormat(format.value)}
                                            className={`p-4 rounded-xl border-2 transition-all duration-300 ${targetFormat === format.value
                                                ? 'border-cyan-400 bg-cyan-400 bg-opacity-20 shadow-lg shadow-cyan-400/25'
                                                : 'border-white border-opacity-20 bg-white bg-opacity-5 hover:bg-opacity-10 hover:border-opacity-40'
                                                }`}
                                        >
                                            <div className="flex items-center justify-center">
                                                <File className="h-6 w-6 text-white mr-2" />
                                                <span className="text-white font-medium">{format.label}</span>
                                            </div>
                                        </button>
                                    ))}
                                </div>
                            </div>
                        )}

                        {/* Convert Button */}
                        {file && targetFormat && (
                            <div className="mb-8">
                                <button
                                    onClick={handleConvert}
                                    disabled={isUploading || isConverting}
                                    className="w-full bg-gradient-to-r from-cyan-500 to-purple-600 hover:from-cyan-600 hover:to-purple-700 disabled:from-gray-500 disabled:to-gray-600 text-white font-bold py-6 px-8 rounded-2xl transition-all duration-300 transform hover:scale-105 disabled:scale-100 shadow-2xl hover:shadow-cyan-500/25"
                                >
                                    <div className="flex items-center justify-center">
                                        {isUploading ? (
                                            <>
                                                <RefreshCw className="animate-spin h-6 w-6 mr-3" />
                                                Uploading...
                                            </>
                                        ) : isConverting ? (
                                            <>
                                                <RefreshCw className="animate-spin h-6 w-6 mr-3" />
                                                Converting...
                                            </>
                                        ) : (
                                            <>
                                                <Zap className="h-6 w-6 mr-3" />
                                                Convert File
                                            </>
                                        )}
                                    </div>
                                </button>
                            </div>
                        )}

                        {/* Error Display */}
                        {error && (
                            <div className="mb-8 bg-red-500 bg-opacity-20 backdrop-blur-lg border border-red-400 border-opacity-50 rounded-2xl p-6">
                                <div className="flex items-center">
                                    <XCircle className="h-6 w-6 text-red-400 mr-3" />
                                    <p className="text-red-200 font-medium">{error}</p>
                                </div>
                            </div>
                        )}

                        {/* Success Result */}
                        {conversionResult && (
                            <div className="bg-green-500 bg-opacity-20 backdrop-blur-lg border border-green-400 border-opacity-50 rounded-2xl p-6">
                                <div className="text-center">
                                    <div className="flex justify-center mb-4">
                                        <CheckCircle className="h-12 w-12 text-green-400" />
                                    </div>
                                    <h3 className="text-white text-xl font-semibold mb-4">
                                        Conversion Complete!
                                    </h3>
                                    <div className="space-y-4">
                                        <a
                                            href={conversionResult.download_url}
                                            download
                                            className="inline-flex items-center bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-600 hover:to-emerald-700 text-white font-bold py-4 px-8 rounded-xl transition-all duration-300 transform hover:scale-105 shadow-lg"
                                        >
                                            <Download className="h-5 w-5 mr-2" />
                                            Download Converted File
                                        </a>
                                        <div>
                                            <button
                                                onClick={resetForm}
                                                className="text-purple-200 hover:text-white underline transition-colors"
                                            >
                                                Convert Another File
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            </div>

            {/* Footer */}
            <footer className="relative">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
                    <div className="text-center">
                        <p className="text-purple-200 text-lg">
                            Powered by AWS Serverless Architecture
                        </p>
                        <div className="flex justify-center items-center mt-4 space-x-6">
                            <div className="flex items-center text-purple-300">
                                <Shield className="h-5 w-5 mr-2" />
                                <span>Secure</span>
                            </div>
                            <div className="flex items-center text-purple-300">
                                <Zap className="h-5 w-5 mr-2" />
                                <span>Fast</span>
                            </div>
                            <div className="flex items-center text-purple-300">
                                <Globe className="h-5 w-5 mr-2" />
                                <span>Scalable</span>
                            </div>
                        </div>
                    </div>
                </div>
            </footer>
        </div>
    );
};

export default FileConverter;
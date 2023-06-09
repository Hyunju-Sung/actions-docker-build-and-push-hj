name: 'Build Docker Image'
description: 'Build Docker Image'

inputs:
  service:
    description: for ECR Repository Name
    required: true
  dockerfile-path:
    description: dockerfile-absolute-path
    required: true
  tag:
    description: The tag name
    required: true
  env:
    description: environment (stg, prd)
    required: true
  custom-docker-build-command:
    description: docker-build-command
    default: ''
  custom-docker-image-name:
    description: docker-image-name
    default: ''
  custom-docker-tag:
    description: custom-docker-tag
    default: latest

runs:
  using: 'composite'
  steps:

    - name: Login to Amazon ECR Private
      id: login-ecr
      uses: Hyunju-Sung/actions-ecr-login-hj@0.0.4

    - name: Build Docker Image with dockerfile
      if: ${{ inputs.custom-docker-build-command == '' && inputs.custom-docker-image-name == '' && inputs.env == 'stg' && env.TAG_ALREADY_EXIST != 'true' }}
      env:
        ECR_REGISTRY: ${{ env.ECR_REGISTRY }}
        ECR_REPOSITORY: ${{ env.ecr-root }}/${{ inputs.env }}/${{ inputs.service }}
        IMAGE_TAG: ${{ inputs.tag }}
        CACHE_FILE: /tmp/docker-image-cache.tar.gz
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG . --file ${{ inputs.dockerfile-path }}
        docker save $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG | gzip > $CACHE_FILE
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG


      shell: bash

    - name: Build Docker Image with command
      if: ${{ inputs.custom-docker-build-command != '' && inputs.custom-docker-image-name != '' && inputs.env == 'stg' }}
      env:
        ECR_REGISTRY: ${{ env.ECR_REGISTRY }}
        ECR_REPOSITORY: ${{ env.ecr-root }}/${{ inputs.env }}/${{ inputs.service }}
        IMAGE_TAG: ${{ inputs.tag }}
        CACHE_FILE: /tmp/docker-image-cache.tar.gz
      run: |
        ${{ inputs.custom-docker-build-command }}
        docker tag ${{ inputs.custom-docker-image-name }}:${{ inputs.custom-docker-tag }} $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker save $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG | gzip > $CACHE_FILE
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
      shell: bash

    - name: Cache Docker layers
      if: ${{ inputs.env == 'stg' }}
      uses: actions/cache@v2
      with:
        path: /tmp/docker-image-cache.tar.gz
        key: ${{ runner.os }}-docker-cache-${{ github.sha }}
        restore-keys: |
          ${{ runner.os }}-docker-cache-

    - name: Restore Docker image cache
      if: ${{ inputs.env == 'prd' }}
      uses: actions/cache@v2
      with:
        path: /tmp/docker-image-cache.tar.gz
        key: ${{ runner.os }}-docker-cache-${{ github.sha }}
        restore-keys: |
          ${{ runner.os }}-docker-cache-

    - name: Load cached Docker image
      if: ${{ inputs.env == 'prd' }}
      env:
        ECR_REGISTRY: ${{ env.ECR_REGISTRY }}
        ECR_REPOSITORY: ${{ env.ecr-root }}/${{ inputs.env }}/${{ inputs.service }}
        CACHE_FILE: /tmp/docker-image-cache.tar.gz
        NEW_IMAGE_TAG: ${{ inputs.tag }}
      run: |
        if [ -f "$CACHE_FILE" ]; then
          echo "Loading image from cache..."
          LOADING_RESULT=$(gunzip -c $CACHE_FILE | docker load)
          echo "$LOADING_RESULT"
          LOADED_IMAGE=$(echo "$LOADING_RESULT" | grep -oP '(?<=Loaded image: ).*')
          echo "Loaded Image: $LOADED_IMAGE"
          if [ -n "$LOADED_IMAGE" ]; then
            docker tag $LOADED_IMAGE $ECR_REGISTRY/$ECR_REPOSITORY:$NEW_IMAGE_TAG
            docker push $ECR_REGISTRY/$ECR_REPOSITORY:$NEW_IMAGE_TAG
          else
            echo "Failed to retrieve loaded image."
          fi
        else
          echo "Cache file not found."
        fi
      shell: bash



    #1. command 로 docker build 하기
    #2. cicd-tutorial / stg||prd / cicd-python-tutorial -- 그러면.. stg 랑 prd push 하는 디렉토리가 다름
    #3. cicd-tutorial/ prd / cicd-python-tutorial:0.0.0-:
    #(stg)
    #SHA 를 보고// 이미 ECR 에 태그가 찍혀있으면 >> 뒷 단에서 new_stg_tag 를 그 태그로 덮어쓴다.  (docker-build-and-push ,그리고 ECR 에는 푸쉬를 안 한다 (태그 안 한다) )
    #job pass *
    #ECR Repository 수정

